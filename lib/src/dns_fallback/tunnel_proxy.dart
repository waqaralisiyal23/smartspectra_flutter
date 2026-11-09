import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'fallback_connector.dart';

void _log(String message) => debugPrint('smartspectra_flutter (dns): $message');

/// A tiny HTTP CONNECT proxy on the phone's loopback interface, through which
/// the SmartSpectra SDK reaches Presage's servers when DNS fallback is on.
///
/// The SDK does its networking in libcurl inside its native library, so a
/// Dart `HttpClient.connectionFactory` (how the GiftList and Sugar Pulse apps
/// fall back) never sees it. libcurl does honour `https_proxy`, so the plugin
/// points it here. For each `CONNECT host:443` the proxy resolves the host
/// with [FallbackConnector] (phone DNS, then DNS-over-HTTPS) and then only
/// copies bytes: TLS runs end to end between the SDK and Presage, with the
/// real hostname's certificate checked by the SDK. The proxy never sees the
/// content.
///
/// Only [allowHost] hosts on [allowedPort] are tunnelled, and it listens on
/// 127.0.0.1 only, so it is not a general-purpose proxy.
class DnsFallbackProxy {
  DnsFallbackProxy({
    required this.allowHost,
    this.allowedPort = 443,
    FallbackConnector? connector,
  }) : _connector = connector ?? FallbackConnector();

  final bool Function(String host) allowHost;
  final int allowedPort;
  final FallbackConnector _connector;

  /// A request line and headers never need more than this.
  static const int _maxHeaderBytes = 8 * 1024;
  static const Duration _headerTimeout = Duration(seconds: 10);

  ServerSocket? _server;
  final Set<Socket> _sockets = {};

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  /// Starts listening on a free loopback port and returns it.
  Future<int> start() async {
    final running = _server;
    if (running != null) return running.port;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      (client) => unawaited(_handle(client)),
      // iOS may reclaim a listening socket while the app is suspended; the
      // plugin starts a new proxy on the next configure/start.
      onDone: () {
        if (identical(_server, server)) _server = null;
      },
      onError: (Object e) => _log('Proxy stopped listening: $e'),
    );
    _log('DNS fallback proxy listening on 127.0.0.1:${server.port}');
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
    for (final socket in [..._sockets]) {
      socket.destroy();
    }
    _sockets.clear();
  }

  Future<void> _handle(Socket client) async {
    _sockets.add(client);
    final buffer = BytesBuilder(copy: false);
    final headerDone = Completer<Uint8List?>();
    late final StreamSubscription<Uint8List> fromClient;
    fromClient = client.listen(
      (chunk) {
        if (headerDone.isCompleted) return;
        buffer.add(chunk);
        if (buffer.length > _maxHeaderBytes) {
          headerDone.complete(null);
        } else if (_headerEnd(buffer.toBytes()) >= 0) {
          fromClient.pause();
          headerDone.complete(buffer.takeBytes());
        }
      },
      onError: (Object _) {
        if (!headerDone.isCompleted) headerDone.complete(null);
      },
      onDone: () {
        if (!headerDone.isCompleted) headerDone.complete(null);
      },
      cancelOnError: true,
    );

    final bytes = await headerDone.future.timeout(
      _headerTimeout,
      onTimeout: () => null,
    );
    if (bytes == null) {
      _close(client);
      return;
    }
    final end = _headerEnd(bytes);
    final target = _parseConnect(
      ascii.decode(bytes.sublist(0, end), allowInvalid: true),
    );
    if (target == null) {
      _reply(client, '405 Method Not Allowed');
      return;
    }
    if (!allowHost(target.host) || target.port != allowedPort) {
      _log('Refused CONNECT to ${target.host}:${target.port}');
      _reply(client, '403 Forbidden');
      return;
    }

    final Socket upstream;
    try {
      upstream = await _connector.connect(target.host, target.port);
    } on Object catch (e) {
      _log('Could not reach ${target.host}: $e');
      _reply(client, '502 Bad Gateway');
      return;
    }
    _sockets.add(upstream);

    void closeBoth() {
      _close(client);
      _close(upstream);
    }

    client.add(ascii.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
    // Anything the client sent after the request headers belongs upstream.
    final early = bytes.sublist(end + 4);
    if (early.isNotEmpty) upstream.add(early);

    upstream.listen(
      client.add,
      onError: (Object _) => closeBoth(),
      onDone: closeBoth,
      cancelOnError: true,
    );
    fromClient
      ..onData(upstream.add)
      ..onError((Object _) => closeBoth())
      ..onDone(closeBoth)
      ..resume();
  }

  void _reply(Socket client, String status) {
    client.add(ascii.encode('HTTP/1.1 $status\r\nContent-Length: 0\r\n\r\n'));
    unawaited(
      client
          .flush()
          .whenComplete(() => _close(client))
          .catchError((Object _) {}),
    );
  }

  void _close(Socket socket) {
    _sockets.remove(socket);
    socket.destroy();
  }

  /// Index of the blank line that ends the request headers, or -1.
  static int _headerEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// `CONNECT host:port HTTP/1.1` → host and port; null for anything else.
  /// IPv6 literals are not supported (Presage is reached over IPv4).
  static ({String host, int port})? _parseConnect(String header) {
    final requestLine = header.split('\r\n').first.trim().split(' ');
    if (requestLine.length < 2 || requestLine[0].toUpperCase() != 'CONNECT') {
      return null;
    }
    final authority = requestLine[1];
    final colon = authority.lastIndexOf(':');
    if (colon <= 0 || authority.startsWith('[')) return null;
    final port = int.tryParse(authority.substring(colon + 1));
    if (port == null) return null;
    return (host: authority.substring(0, colon).toLowerCase(), port: port);
  }
}
