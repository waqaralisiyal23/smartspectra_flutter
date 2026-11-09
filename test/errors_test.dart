import 'package:flutter_test/flutter_test.dart';
import 'package:smartspectra_flutter/smartspectra_flutter.dart';

void main() {
  group('SmartSpectraException.fromNative', () {
    test('keeps known codes in both native spellings', () {
      expect(
        SmartSpectraException.fromNative(code: 'AUTHENTICATION_FAILED', message: 'bad key').code,
        SmartSpectraErrorCode.authenticationFailed,
      );
      expect(
        SmartSpectraException.fromNative(code: 'creditExhausted', message: 'none left').code,
        SmartSpectraErrorCode.creditExhausted,
      );
    });

    test('unknown codes become unknown, keeping retryable', () {
      final e = SmartSpectraException.fromNative(code: 'SOMETHING_NEW', message: 'x', retryable: true);
      expect(e.code, SmartSpectraErrorCode.unknown);
      expect(e.retryable, isTrue);
    });

    for (final message in [
      'COULDNT_RESOLVE_HOST cont-api.physiology.presagetech.com',
      "Couldn't resolve host name",
      'Could not resolve host: cont-api.physiology.presagetech.com',
      'Unable to resolve host "cont-api.physiology.presagetech.com": No address associated with hostname',
      'java.net.UnknownHostException: cont-api',
      'A server with the specified hostname could not be found.',
      'The Internet connection appears to be offline.',
      'Network is unreachable',
    ]) {
      test('connectivity failure → networkError, retryable: "$message"', () {
        for (final code in ['PROCESSING_FAILED', 'serverError', 'unknown', null]) {
          final e = SmartSpectraException.fromNative(code: code, message: message);
          expect(e.code, SmartSpectraErrorCode.networkError);
          expect(e.retryable, isTrue);
          expect(e.message, message);
        }
      });
    }

    test('fromMap goes through the same mapping', () {
      final e = SmartSpectraException.fromMap({
        'code': 'PROCESSING_FAILED',
        'message': 'curl error: COULDNT_RESOLVE_HOST',
        'retryable': false,
      });
      expect(e.code, SmartSpectraErrorCode.networkError);
    });

    test('ordinary failures are not mistaken for network problems', () {
      final e = SmartSpectraException.fromNative(code: 'PROCESSING_FAILED', message: 'Model failed to load');
      expect(e.code, SmartSpectraErrorCode.processingFailed);
    });
  });
}
