import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'doh_resolver.dart';

void _log(String message) => debugPrint('smartspectra_flutter (dns): $message');

/// Opens a plain TCP connection to a host: the phone's DNS first, and
/// [DohResolver]'s answer when the phone's DNS cannot find it.
///
/// The same rules as the GiftList / Sugar Pulse `DnsFallbackConnector`, minus
/// TLS (the SDK does its own, end to end, through the tunnel):
///
/// * only a failed *lookup* falls back; a failed connection is the server's or
///   the network's, and public DNS would not change it;
/// * while a fallback answer is fresh it is used straight away, rather than
///   waiting for the phone's DNS to fail again;
/// * each address gets [addressTimeout] before the next is tried, and an
///   answer none of whose addresses connect is dropped.
class FallbackConnector {
  FallbackConnector({
    DohResolver? resolver,
    SystemLookup? systemLookup,
    this.addressTimeout = const Duration(seconds: 5),
  }) : _resolver = resolver ?? DohResolver(),
       _systemLookup = systemLookup ?? InternetAddress.lookup;

  final DohResolver _resolver;
  final SystemLookup _systemLookup;
  final Duration addressTimeout;

  Future<Socket> connect(String host, int port) async {
    var addresses = _resolver.cached(host);
    var fromFallback = addresses != null;
    if (addresses == null) {
      try {
        addresses = await _systemLookup(host);
      } on SocketException catch (e) {
        _log('Phone DNS could not find $host ($e), asking over HTTPS');
        addresses = await _resolver.resolve(host);
        fromFallback = true;
      }
    }
    SocketException? lastError;
    for (final address in addresses) {
      try {
        return await Socket.connect(address, port, timeout: addressTimeout);
      } on SocketException catch (e) {
        _log('Could not connect to $host at ${address.address}: $e');
        lastError = e;
      }
    }
    if (fromFallback) {
      // Ask the phone's DNS again next time rather than reusing a dead answer.
      _resolver.forget(host);
    }
    throw lastError ?? SocketException('No address for $host');
  }
}
