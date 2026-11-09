import 'package:flutter/foundation.dart';
import 'proxy_env.dart';
import 'tunnel_proxy.dart';

/// Turns DNS fallback for the SDK on and off: runs [DnsFallbackProxy] and
/// points the SDK's libcurl at it with `https_proxy`.
class DnsFallback {
  DnsFallback._();

  static final DnsFallback instance = DnsFallback._();

  /// Presage's servers, and nothing else, go through the tunnel.
  static bool isPresageHost(String host) =>
      host == 'presagetech.com' || host.endsWith('.presagetech.com');

  static const List<String> _variables = ['https_proxy', 'HTTPS_PROXY'];

  final DnsFallbackProxy _proxy = DnsFallbackProxy(allowHost: isPresageHost);

  bool get isEnabled => _proxy.isRunning;

  /// Safe to call again: restarts the proxy if the OS closed it (iOS can,
  /// while the app is suspended) and re-points the SDK at its port.
  Future<void> enable() async {
    final port = await _proxy.start();
    final url = 'http://127.0.0.1:$port';
    for (final name in _variables) {
      ProcessEnv.set(name, url);
    }
    debugPrint('smartspectra_flutter (dns): fallback on ($url)');
  }

  Future<void> disable() async {
    if (!_proxy.isRunning) return;
    for (final name in _variables) {
      ProcessEnv.unset(name);
    }
    await _proxy.stop();
  }
}
