import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartspectra_flutter/smartspectra_flutter.dart';
import 'package:smartspectra_flutter/src/parse.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('smartspectra_flutter/methods');

  test('status parsing copes with Swift enum printing', () {
    expect(parseStatus('running'), ProcessingStatus.running);
    expect(parseStatus('RUNNING'), ProcessingStatus.running);
    expect(parseStatus('error("Could not resolve host")'), ProcessingStatus.error);
    expect(parseStatus('ProcessingStatus.starting'), ProcessingStatus.starting);
    expect(parseStatus('stopped'), ProcessingStatus.idle);
    expect(parseStatus('somethingNew'), ProcessingStatus.idle);
    expect(parseStatus(null), ProcessingStatus.idle);
  });

  group('configure', () {
    late List<String> calls;

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methods, null);
    });

    void mockNative({required bool failFirstConfigure, String message = 'Select an input while SmartSpectra is stopped.'}) {
      calls = [];
      var configures = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call.method);
        if (call.method == 'configure' && failFirstConfigure && configures++ == 0) {
          throw PlatformException(code: 'unknown', message: message);
        }
        return null;
      });
    }

    test('resets the SDK and retries when it is not fully stopped (iOS)', () async {
      mockNative(failFirstConfigure: true);
      await SmartSpectra.instance.configure(const SmartSpectraConfig(apiKey: 'key'));
      expect(calls, ['configure', 'reset', 'configure']);
    });

    test('other configure errors are not retried', () async {
      mockNative(failFirstConfigure: true, message: 'Bad key');
      await expectLater(
        SmartSpectra.instance.configure(const SmartSpectraConfig(apiKey: 'key')),
        throwsA(isA<SmartSpectraException>()),
      );
      expect(calls, ['configure']);
    });
  });
}
