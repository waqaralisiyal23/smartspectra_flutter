import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'tunnel_proxy.dart' show DnsFallbackProxy;

// Ported from the GiftList / Sugar Pulse apps' `dns_fallback.dart`
// (`DohResolver`), behaviour unchanged.

void _log(String message) => debugPrint('smartspectra_flutter (dns): $message');

/// Asks for one URL and returns the response body, throwing on any failure.
typedef DohFetch = Future<String> Function(Uri uri);

/// Looks the phone's DNS up for a host, throwing a [SocketException] when it
/// cannot find it.
typedef SystemLookup = Future<List<InternetAddress>> Function(String host);

/// Looks a hostname up over DNS-over-HTTPS, for when the phone's own DNS
/// cannot.
///
/// Some home routers and ISPs' DNS servers cannot resolve Presage's servers
/// (`*.presagetech.com`), while Cloudflare's and Google's public resolvers
/// still answer. Those are asked directly over HTTPS: they are addressed by
/// IP, so asking needs no DNS of its own, and their certificates name those
/// IPs.
///
/// An answer only says where to connect. The SDK's TLS connection, tunnelled
/// through [DnsFallbackProxy], is still checked against the real hostname's
/// certificate, so a wrong answer fails the handshake instead of reaching
/// another server.
class DohResolver {
  /// Tried in order until one answers.
  static final List<Uri> defaultProviders = <Uri>[
    Uri.parse('https://1.1.1.1/dns-query'),
    Uri.parse('https://8.8.8.8/resolve'),
  ];

  /// Answers are kept for their TTL within these bounds: at least a minute,
  /// so a zero TTL is not asked for again on every connection, and at most an
  /// hour, so a moved server is found soon after.
  static const Duration minTtl = Duration(minutes: 1);
  static const Duration maxTtl = Duration(hours: 1);

  /// IPv4 only: every network the fallback is for reaches Presage over IPv4.
  static const int _typeA = 1;

  final List<Uri> providers;
  final DohFetch _fetch;
  final DateTime Function() _now;
  final Map<String, ({List<InternetAddress> addresses, DateTime expiresAt})>
  _answers = {};
  final Map<String, Future<List<InternetAddress>>> _inFlight = {};

  DohResolver({List<Uri>? providers, DohFetch? fetch, DateTime Function()? now})
    : providers = providers ?? defaultProviders,
      _fetch = fetch ?? _fetchOverHttps,
      _now = now ?? DateTime.now;

  /// The last answer for [host], while it is still fresh.
  List<InternetAddress>? cached(String host) {
    final answer = _answers[host];
    if (answer == null || !_now().isBefore(answer.expiresAt)) {
      return null;
    }
    return answer.addresses;
  }

  /// Drops the answer for [host], so the next connection asks the phone's
  /// DNS again — none of its addresses could be reached.
  void forget(String host) => _answers.remove(host);

  /// The addresses for [host], from the cache or the first provider that
  /// answers. Connections that fall back together share one query. Throws a
  /// [SocketException] when no provider has an address.
  Future<List<InternetAddress>> resolve(String host) {
    final fresh = cached(host);
    if (fresh != null) {
      return Future.value(fresh);
    }
    // A block body: whenComplete waits on a returned future, and the one
    // removed is this one.
    return _inFlight[host] ??= _query(host).whenComplete(() {
      _inFlight.remove(host);
    });
  }

  Future<List<InternetAddress>> _query(String host) async {
    for (final provider in providers) {
      try {
        final body = await _fetch(
          provider.replace(queryParameters: {'name': host, 'type': 'A'}),
        );
        final answer = _parse(body);
        if (answer == null) {
          _log('${provider.host} has no address for $host');
          continue;
        }
        _answers[host] = (
          addresses: answer.addresses,
          expiresAt: _now().add(answer.ttl),
        );
        return answer.addresses;
      } catch (e) {
        _log('${provider.host} could not look up $host: $e');
      }
    }
    throw SocketException('DNS-over-HTTPS found no address for $host');
  }

  /// The A records of a JSON DNS answer, with the shortest TTL among them;
  /// null for a failed lookup or one without any.
  static ({List<InternetAddress> addresses, Duration ttl})? _parse(
    String body,
  ) {
    final json = jsonDecode(body);
    if (json is! Map || json['Status'] != 0 || json['Answer'] is! List) {
      return null;
    }
    final addresses = <InternetAddress>[];
    int? ttlSeconds;
    for (final record in json['Answer'] as List) {
      if (record is! Map || record['type'] != _typeA) {
        continue;
      }
      final data = record['data'];
      final address = data is String ? InternetAddress.tryParse(data) : null;
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      addresses.add(address);
      final ttl = record['TTL'];
      if (ttl is int) {
        ttlSeconds = ttlSeconds == null ? ttl : min(ttlSeconds, ttl);
      }
    }
    if (addresses.isEmpty) {
      return null;
    }
    final ttl = Duration(seconds: ttlSeconds ?? 0);
    return (
      addresses: addresses,
      ttl: ttl < minTtl ? minTtl : (ttl > maxTtl ? maxTtl : ttl),
    );
  }

  /// How long one provider has to answer, all told. A network that drops
  /// traffic rather than refusing it — captive Wi-Fi, say — then fails a
  /// request within a few seconds of the phone's DNS, not after one
  /// timeout per step per provider.
  static const Duration providerTimeout = Duration(seconds: 4);

  static Future<String> _fetchOverHttps(Uri uri) async {
    final client = HttpClient()..connectionTimeout = providerTimeout;
    try {
      return await _get(client, uri).timeout(providerTimeout);
    } finally {
      // Also abandons whatever the timeout left running.
      client.close(force: true);
    }
  }

  static Future<String> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return body;
  }
}
