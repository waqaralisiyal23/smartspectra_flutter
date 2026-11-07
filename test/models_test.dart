import 'package:flutter_test/flutter_test.dart';
import 'package:smartspectra_flutter/smartspectra_flutter.dart';

void main() {
  test('parses a full metrics payload from Android-style names', () {
    final m = SmartSpectraMetrics.fromMap({
      'pulseRate': {'value': 72.4, 'confidence': 81.0, 'stable': true, 'timestamp': 1000},
      'breathingRate': {'value': 14, 'confidence': 50.0, 'stable': true, 'timestamp': 1000},
      'hrv': {
        'rmssd': 42.0,
        'sdnn': 50.0,
        'meanNn': 830.0,
        'baevsky': 120.0,
        'confidence': 60.0,
        'stable': true,
        'timestamp': 1000,
      },
      'expression': {
        'scores': {'ANGRY': 70.0, 'HAPPY': 10.0, 'UNKNOWN_THING': 99.0},
        'stable': true,
        'timestamp': 1000,
      },
      'blinking': {'detected': true, 'stable': true, 'timestamp': 1000},
      'pulseTrace': {
        't': [1, 2, 3],
        'v': [0.1, 0.2, 0.3],
      },
    });

    expect(m.pulseRate!.value, closeTo(72.4, 1e-9));
    expect(m.breathingRate!.value, 14);
    expect(m.hrv!.rmssd, 42);
    expect(m.expression!.dominant, Expression.angry);
    expect(m.expression![Expression.happy], 10);
    expect(m.expression!.scores.length, 2);
    expect(m.blinking!.detected, isTrue);
    expect(m.talking, isNull);
    expect(m.pulseTrace.length, 3);
    expect(m.breathingTrace, isEmpty);
  });

  test('parses Swift-style enum names', () {
    final v = ValidationStatus.fromMap({'code': 'faceNotCentered', 'hint': 'Center your face'});
    expect(v.code, ValidationCode.faceNotCentered);

    final k = ValidationStatus.fromMap({'code': 'FACE_NOT_CENTERED', 'hint': ''});
    expect(k.code, ValidationCode.faceNotCentered);

    final e = SmartSpectraException.fromMap({'code': 'creditExhausted', 'message': 'No credits'});
    expect(e.code, SmartSpectraErrorCode.creditExhausted);

    final u = SmartSpectraException.fromMap({'code': 'SOMETHING_NEW', 'message': 'x'});
    expect(u.code, SmartSpectraErrorCode.unknown);
  });

  test('config serializes metric names', () {
    const config = SmartSpectraConfig(
      apiKey: 'k',
      metrics: {SmartSpectraMetric.cardio, SmartSpectraMetric.expressions},
    );
    final map = config.toMap();
    expect(map['metrics'], containsAll(['cardio', 'expressions']));
    expect(map['enableTelemetry'], isFalse);
    expect(map['camera'], 'front');
  });

  test('newBlinks counts blinks in one update and defaults to 0', () {
    final m = SmartSpectraMetrics.fromMap({
      'blinking': {'detected': false, 'stable': true, 'timestamp': 3},
      'newBlinks': 2,
    });
    expect(m.newBlinks, 2);
    expect(m.blinking?.detected, isFalse);
    expect(SmartSpectraMetrics.fromMap({}).newBlinks, 0);
  });
}
