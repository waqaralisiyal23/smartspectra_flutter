import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartspectra_flutter/src/dns_fallback/dns_fallback.dart';
import 'package:smartspectra_flutter/src/dns_fallback/doh_resolver.dart';
import 'package:smartspectra_flutter/src/dns_fallback/fallback_connector.dart';
import 'package:smartspectra_flutter/src/dns_fallback/proxy_env.dart';
import 'package:smartspectra_flutter/src/dns_fallback/tunnel_proxy.dart';

/// A JSON DNS answer as Cloudflare's and Google's resolvers send it.
String _answer(List<String> addresses, {int ttl = 300, int status = 0}) =>
    jsonEncode(<String, dynamic>{
      'Status': status,
      'Answer': <Map<String, dynamic>>[
        for (final address in addresses)
          <String, dynamic>{
            'name': 'cont-api.physiology.presagetech.com',
            'type': 1,
            'TTL': ttl,
            'data': address,
          },
      ],
    });

Future<Never> _phoneCannotFind(String _) async =>
    throw const SocketException('Failed host lookup');

DohResolver _loopbackResolver(
  List<String> asked, [
  List<String> addresses = const ['127.0.0.1'],
]) => DohResolver(
  providers: [Uri.parse('https://1.1.1.1/dns-query')],
  fetch: (uri) async {
    asked.add(uri.queryParameters['name']!);
    return _answer(addresses);
  },
);

/// Sends [request] to the proxy and returns the response line, plus the
/// socket for tunnelling.
Future<(String, Socket)> _connectThrough(int proxyPort, String request) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, proxyPort);
  final received = StreamController<List<int>>();
  socket.listen(received.add, onDone: received.close);
  socket.add(ascii.encode(request));
  final iterator = StreamIterator(received.stream);
  final bytes = <int>[];
  while (!ascii.decode(bytes, allowInvalid: true).contains('\r\n\r\n') &&
      await iterator.moveNext()) {
    bytes.addAll(iterator.current);
  }
  final text = ascii.decode(bytes, allowInvalid: true);
  addTearDown(socket.destroy);
  // Hand the rest of the stream back for tunnel tests.
  _rest[socket] = iterator;
  return (text.split('\r\n').first, socket);
}

final _rest = Expando<StreamIterator<List<int>>>();

void main() {
  const host = 'cont-api.physiology.presagetech.com';
  final cloudflare = Uri.parse('https://1.1.1.1/dns-query');
  final google = Uri.parse('https://8.8.8.8/resolve');

  // Ported unchanged from the GiftList app's tests.
  group('DohResolver', () {
    test('asks for the A record and reads its addresses', () async {
      final asked = <Uri>[];
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        fetch: (uri) async {
          asked.add(uri);
          return _answer(<String>['104.21.1.1', '172.67.1.1']);
        },
      );

      final addresses = await resolver.resolve(host);

      expect(addresses.map((a) => a.address), <String>[
        '104.21.1.1',
        '172.67.1.1',
      ]);
      expect(asked.single.queryParameters, <String, String>{
        'name': host,
        'type': 'A',
      });
    });

    test('reads A records only, skipping CNAMEs and anything else', () async {
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        fetch: (_) async => jsonEncode(<String, dynamic>{
          'Status': 0,
          'Answer': <Map<String, dynamic>>[
            <String, dynamic>{'type': 5, 'TTL': 300, 'data': 'edge.net.'},
            <String, dynamic>{'type': 1, 'TTL': 300, 'data': '104.21.1.1'},
            <String, dynamic>{'type': 1, 'TTL': 300, 'data': 'not an address'},
          ],
        }),
      );

      expect((await resolver.resolve(host)).map((a) => a.address), <String>[
        '104.21.1.1',
      ]);
    });

    test('keeps an answer for its shortest TTL', () async {
      var now = DateTime.utc(2026, 10, 29, 12);
      var fetches = 0;
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        now: () => now,
        fetch: (_) async {
          fetches++;
          return jsonEncode(<String, dynamic>{
            'Status': 0,
            'Answer': <Map<String, dynamic>>[
              <String, dynamic>{'type': 1, 'TTL': 600, 'data': '104.21.1.1'},
              <String, dynamic>{'type': 1, 'TTL': 300, 'data': '172.67.1.1'},
            ],
          });
        },
      );

      await resolver.resolve(host);
      now = now.add(const Duration(seconds: 299));
      expect(resolver.cached(host), hasLength(2));

      now = now.add(const Duration(seconds: 1));
      expect(resolver.cached(host), isNull);
      await resolver.resolve(host);
      expect(fetches, 2);
    });

    test('moves on to the next provider when one fails', () async {
      final resolver = DohResolver(
        providers: <Uri>[cloudflare, google],
        fetch: (uri) async {
          if (uri.host == cloudflare.host) {
            throw const SocketException('unreachable');
          }
          return _answer(<String>['104.21.1.1']);
        },
      );

      expect((await resolver.resolve(host)).single.address, '104.21.1.1');
    });

    test('moves on from an answer without an address', () async {
      final resolver = DohResolver(
        providers: <Uri>[cloudflare, google],
        fetch: (uri) async => uri.host == cloudflare.host
            ? _answer(<String>[], status: 3)
            : _answer(<String>['104.21.1.1']),
      );

      expect((await resolver.resolve(host)).single.address, '104.21.1.1');
    });

    test('throws a SocketException when no provider has an address', () async {
      final resolver = DohResolver(
        providers: <Uri>[cloudflare, google],
        fetch: (_) async => throw const SocketException('unreachable'),
      );

      await expectLater(
        resolver.resolve(host),
        throwsA(isA<SocketException>()),
      );
    });

    test('keeps an answer for its TTL, at least a minute', () async {
      var now = DateTime.utc(2026, 10, 29, 12);
      var fetches = 0;
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        now: () => now,
        fetch: (_) async {
          fetches++;
          return _answer(<String>['104.21.1.1'], ttl: 0);
        },
      );

      await resolver.resolve(host);
      now = now.add(const Duration(seconds: 59));
      expect(resolver.cached(host), isNotNull);
      await resolver.resolve(host);
      expect(fetches, 1);

      now = now.add(const Duration(seconds: 1));
      expect(resolver.cached(host), isNull);
      await resolver.resolve(host);
      expect(fetches, 2);
    });

    test('keeps an answer for an hour at most', () async {
      var now = DateTime.utc(2026, 10, 29, 12);
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        now: () => now,
        fetch: (_) async => _answer(<String>['104.21.1.1'], ttl: 86400),
      );

      await resolver.resolve(host);
      now = now.add(const Duration(hours: 1));

      expect(resolver.cached(host), isNull);
    });

    test('lookups at the same time share one query', () async {
      var fetches = 0;
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        fetch: (_) async {
          fetches++;
          return _answer(<String>['104.21.1.1']);
        },
      );

      await Future.wait(<Future<List<InternetAddress>>>[
        resolver.resolve(host),
        resolver.resolve(host),
      ]);

      expect(fetches, 1);
    });

    test('asks again after a lookup that found nothing', () async {
      var fetches = 0;
      final resolver = DohResolver(
        providers: <Uri>[cloudflare],
        fetch: (_) async {
          if (++fetches == 1) {
            throw const SocketException('unreachable');
          }
          return _answer(<String>['104.21.1.1']);
        },
      );

      await expectLater(
        resolver.resolve(host),
        throwsA(isA<SocketException>()),
      );
      expect((await resolver.resolve(host)).single.address, '104.21.1.1');
      expect(fetches, 2);
    });
  });

  group('FallbackConnector', () {
    late ServerSocket server;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) => socket.destroy());
    });

    tearDown(() => server.close());

    test(
      'uses the phone DNS when it answers, asking nothing over HTTPS',
      () async {
        final asked = <String>[];
        final connector = FallbackConnector(
          resolver: _loopbackResolver(asked),
          systemLookup: (_) async => [InternetAddress.loopbackIPv4],
        );
        (await connector.connect(host, server.port)).destroy();
        expect(asked, isEmpty);
      },
    );

    test('asks over HTTPS when the phone DNS cannot find the host', () async {
      final asked = <String>[];
      final connector = FallbackConnector(
        resolver: _loopbackResolver(asked),
        systemLookup: _phoneCannotFind,
      );
      (await connector.connect(host, server.port)).destroy();
      expect(asked, [host]);
    });

    test(
      'uses a fresh fallback answer without asking the phone again',
      () async {
        var lookups = 0;
        final connector = FallbackConnector(
          resolver: _loopbackResolver([]),
          systemLookup: (h) {
            lookups++;
            return _phoneCannotFind(h);
          },
        );
        (await connector.connect(host, server.port)).destroy();
        (await connector.connect(host, server.port)).destroy();
        expect(lookups, 1);
      },
    );

    test('tries the next address when one cannot be reached', () async {
      final connector = FallbackConnector(
        resolver: _loopbackResolver([], ['255.255.255.255', '127.0.0.1']),
        systemLookup: _phoneCannotFind,
      );
      (await connector.connect(host, server.port)).destroy();
    });

    test('drops a fallback answer none of whose addresses connect', () async {
      final asked = <String>[];
      final connector = FallbackConnector(
        resolver: _loopbackResolver(asked, ['255.255.255.255']),
        systemLookup: _phoneCannotFind,
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          connector.connect(host, server.port),
          throwsA(isA<SocketException>()),
        );
      }
      expect(asked, [
        host,
        host,
      ], reason: 'asked afresh, not the dead answer reused');
    });
  });

  group('DnsFallbackProxy', () {
    late ServerSocket echo;
    late DnsFallbackProxy proxy;
    late List<String> asked;

    setUp(() async {
      // Stands in for Presage: echoes what it receives.
      echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      echo.listen(
        (socket) => socket.listen(socket.add, onDone: socket.destroy),
      );
      asked = [];
      proxy = DnsFallbackProxy(
        allowHost: DnsFallback.isPresageHost,
        allowedPort: echo.port,
        connector: FallbackConnector(
          resolver: _loopbackResolver(asked),
          systemLookup: _phoneCannotFind,
        ),
      );
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await echo.close();
    });

    test('tunnels to Presage through the fallback answer, both ways', () async {
      final (status, socket) = await _connectThrough(
        proxy.port!,
        'CONNECT $host:${echo.port} HTTP/1.1\r\nHost: $host:${echo.port}\r\n\r\n',
      );
      expect(status, 'HTTP/1.1 200 Connection established');
      expect(asked, [host]);

      socket.add(utf8.encode('tls bytes'));
      final rest = _rest[socket]!;
      final echoed = <int>[];
      while (echoed.length < 9 && await rest.moveNext()) {
        echoed.addAll(rest.current);
      }
      expect(utf8.decode(echoed), 'tls bytes');
    });

    test('forwards bytes sent right after the request headers', () async {
      final (status, socket) = await _connectThrough(
        proxy.port!,
        'CONNECT $host:${echo.port} HTTP/1.1\r\n\r\nearly',
      );
      expect(status, 'HTTP/1.1 200 Connection established');
      final rest = _rest[socket]!;
      final echoed = <int>[];
      while (echoed.length < 5 && await rest.moveNext()) {
        echoed.addAll(rest.current);
      }
      expect(utf8.decode(echoed), 'early');
    });

    test('refuses any host that is not Presage', () async {
      final (status, _) = await _connectThrough(
        proxy.port!,
        'CONNECT example.com:${echo.port} HTTP/1.1\r\n\r\n',
      );
      expect(status, 'HTTP/1.1 403 Forbidden');
      expect(asked, isEmpty);
    });

    test('refuses a look-alike host', () async {
      final (status, _) = await _connectThrough(
        proxy.port!,
        'CONNECT evilpresagetech.com:${echo.port} HTTP/1.1\r\n\r\n',
      );
      expect(status, 'HTTP/1.1 403 Forbidden');
    });

    test('refuses other ports', () async {
      final (status, _) = await _connectThrough(
        proxy.port!,
        'CONNECT $host:22 HTTP/1.1\r\n\r\n',
      );
      expect(status, 'HTTP/1.1 403 Forbidden');
    });

    test('is not a plain HTTP proxy', () async {
      final (status, _) = await _connectThrough(
        proxy.port!,
        'GET http://$host/ HTTP/1.1\r\n\r\n',
      );
      expect(status, 'HTTP/1.1 405 Method Not Allowed');
    });

    test('answers 502 when Presage cannot be found at all', () async {
      await proxy.stop();
      proxy = DnsFallbackProxy(
        allowHost: DnsFallback.isPresageHost,
        allowedPort: echo.port,
        connector: FallbackConnector(
          resolver: DohResolver(
            fetch: (_) async => throw const SocketException('offline'),
          ),
          systemLookup: _phoneCannotFind,
        ),
      );
      await proxy.start();
      final (status, _) = await _connectThrough(
        proxy.port!,
        'CONNECT $host:${echo.port} HTTP/1.1\r\n\r\n',
      );
      expect(status, 'HTTP/1.1 502 Bad Gateway');
    });

    test('listens on loopback only', () async {
      expect(proxy.isRunning, isTrue);
      final sockets = await NetworkInterface.list();
      final external = sockets
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback && a.type == InternetAddressType.IPv4);
      for (final address in external.take(1)) {
        await expectLater(
          Socket.connect(
            address,
            proxy.port!,
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<SocketException>()),
        );
      }
    });
  });

  test('Presage hosts', () {
    expect(
      DnsFallback.isPresageHost('cont-api.physiology.presagetech.com'),
      isTrue,
    );
    expect(DnsFallback.isPresageHost('presagetech.com'), isTrue);
    expect(DnsFallback.isPresageHost('evilpresagetech.com'), isFalse);
    expect(DnsFallback.isPresageHost('presagetech.com.evil.net'), isFalse);
  });

  test('sets and clears process environment variables the SDK reads', () {
    ProcessEnv.set('SMARTSPECTRA_TEST_PROXY', 'http://127.0.0.1:1234');
    expect(ProcessEnv.get('SMARTSPECTRA_TEST_PROXY'), 'http://127.0.0.1:1234');
    ProcessEnv.unset('SMARTSPECTRA_TEST_PROXY');
    expect(ProcessEnv.get('SMARTSPECTRA_TEST_PROXY'), isNull);
  });

  test('enable points https_proxy at the proxy; disable clears it', () async {
    await DnsFallback.instance.enable();
    expect(ProcessEnv.get('https_proxy'), startsWith('http://127.0.0.1:'));
    expect(ProcessEnv.get('HTTPS_PROXY'), ProcessEnv.get('https_proxy'));
    await DnsFallback.instance.enable();
    expect(
      DnsFallback.instance.isEnabled,
      isTrue,
      reason: 'enable is idempotent',
    );
    await DnsFallback.instance.disable();
    expect(ProcessEnv.get('https_proxy'), isNull);
    expect(DnsFallback.instance.isEnabled, isFalse);
  });
}
