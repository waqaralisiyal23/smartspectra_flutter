import 'parse.dart';

/// Lifecycle state of the measurement pipeline.
enum ProcessingStatus {
  /// Not running.
  idle,

  /// Initializing (authenticating, opening the camera, loading models).
  starting,

  /// Measuring: metrics are flowing.
  running,

  /// Tearing down; returns to [idle].
  stopping,

  /// Something went wrong; see [SmartSpectra.errors].
  error,
}

/// Why the current frames may not give a good reading.
enum ValidationCode {
  /// Conditions are fine.
  ok,
  noFaceFound,
  multipleFacesFound,
  faceNotCentered,
  faceSizeOutOfRange,
  tooDark,
  tooBright,
  chestNotVisible,
  cameraTuning,
  frameRateTooLow,
  excessiveMotion,
  faceTooClose,
  faceTooFar,
  faceTooHigh,
  faceTooLow,
  faceNotForward,

  /// A code this plugin version does not know about.
  unknown,
}

/// Imaging guidance from the SDK, e.g. "Too dark" or "Face not centered".
class ValidationStatus {
  /// Creates a validation status.
  const ValidationStatus({required this.code, required this.hint});

  /// Parses the platform payload.
  factory ValidationStatus.fromMap(Map<Object?, Object?> map) => ValidationStatus(
        code: parseEnum(ValidationCode.values, map['code'] as String?, ValidationCode.unknown),
        hint: (map['hint'] as String?) ?? '',
      );

  /// Machine-readable reason.
  final ValidationCode code;

  /// User-facing hint text from the SDK (may be empty when [code] is ok).
  final String hint;

  /// Whether imaging conditions are good.
  bool get isOk => code == ValidationCode.ok;

  @override
  String toString() => 'ValidationStatus(${code.name}, "$hint")';
}

/// A single value with confidence, such as pulse rate or breathing rate.
class Reading {
  /// Creates a reading.
  const Reading({
    required this.value,
    required this.confidence,
    required this.stable,
    required this.timestampUs,
  });

  /// Parses the platform payload.
  factory Reading.fromMap(Map<Object?, Object?> map) => Reading(
        value: asDouble(map['value']) ?? 0,
        confidence: asDouble(map['confidence']) ?? 0,
        stable: (map['stable'] as bool?) ?? false,
        timestampUs: asInt(map['timestamp']),
      );

  /// The measured value (BPM for pulse, breaths/min for breathing).
  final double value;

  /// Confidence from 0 to 100.
  final double confidence;

  /// Whether the SDK considers the value stable (confidence above its
  /// internal threshold).
  final bool stable;

  /// Capture time in microseconds since the Unix epoch.
  final int timestampUs;

  /// Capture time as a [DateTime].
  DateTime get timestamp => DateTime.fromMicrosecondsSinceEpoch(timestampUs);

  @override
  String toString() => 'Reading(${value.toStringAsFixed(1)}, conf ${confidence.toStringAsFixed(0)})';
}

/// Heart-rate-variability statistics over a 60-second window.
///
/// [confidence] stays 0 until the full window is collected.
class HrvReading {
  /// Creates an HRV reading.
  const HrvReading({
    required this.rmssd,
    required this.sdnn,
    required this.meanNn,
    required this.baevsky,
    required this.confidence,
    required this.stable,
    required this.timestampUs,
  });

  /// Parses the platform payload.
  factory HrvReading.fromMap(Map<Object?, Object?> map) => HrvReading(
        rmssd: asDouble(map['rmssd']) ?? 0,
        sdnn: asDouble(map['sdnn']) ?? 0,
        meanNn: asDouble(map['meanNn']) ?? 0,
        baevsky: asDouble(map['baevsky']) ?? 0,
        confidence: asDouble(map['confidence']) ?? 0,
        stable: (map['stable'] as bool?) ?? false,
        timestampUs: asInt(map['timestamp']),
      );

  /// Root mean square of successive NN differences, in milliseconds.
  final double rmssd;

  /// Standard deviation of NN intervals, in milliseconds.
  final double sdnn;

  /// Average NN interval, in milliseconds.
  final double meanNn;

  /// Baevsky stress index (unitless). Compare against the same person's
  /// baseline rather than treating it as an absolute score.
  final double baevsky;

  /// Confidence from 0 to 100.
  final double confidence;

  /// Whether the SDK considers the value stable.
  final bool stable;

  /// Capture time in microseconds since the Unix epoch.
  final int timestampUs;
}

/// Facial expressions the SDK classifies.
enum Expression {
  angry,
  contempt,
  disgust,
  fear,
  happy,
  neutral,
  sad,
  surprise,
}

/// Expression probabilities for one frame.
class ExpressionReading {
  /// Creates an expression reading.
  const ExpressionReading({
    required this.scores,
    required this.stable,
    required this.timestampUs,
  });

  /// Parses the platform payload.
  factory ExpressionReading.fromMap(Map<Object?, Object?> map) {
    final raw = (map['scores'] as Map<Object?, Object?>?) ?? const {};
    final scores = <Expression, double>{};
    raw.forEach((key, value) {
      final type = tryParseEnum(Expression.values, key as String?);
      final confidence = asDouble(value);
      if (type != null && confidence != null) scores[type] = confidence;
    });
    return ExpressionReading(
      scores: scores,
      stable: (map['stable'] as bool?) ?? false,
      timestampUs: asInt(map['timestamp']),
    );
  }

  /// Confidence (0–100) per expression.
  final Map<Expression, double> scores;

  /// Whether the SDK considers the reading stable.
  final bool stable;

  /// Capture time in microseconds since the Unix epoch.
  final int timestampUs;

  /// The highest-scoring expression, or `null` when no scores are present.
  Expression? get dominant {
    Expression? best;
    var bestScore = 0.0;
    scores.forEach((type, score) {
      if (score > bestScore) {
        best = type;
        bestScore = score;
      }
    });
    return best;
  }

  /// Confidence (0–100) for [expression], or 0 when absent.
  double operator [](Expression expression) => scores[expression] ?? 0;
}

/// A yes/no detection such as blinking or talking.
class Detection {
  /// Creates a detection.
  const Detection({
    required this.detected,
    required this.stable,
    required this.timestampUs,
  });

  /// Parses the platform payload.
  factory Detection.fromMap(Map<Object?, Object?> map) => Detection(
        detected: (map['detected'] as bool?) ?? false,
        stable: (map['stable'] as bool?) ?? false,
        timestampUs: asInt(map['timestamp']),
      );

  /// Whether the event is happening in this frame.
  final bool detected;

  /// Whether the SDK considers the detection stable.
  final bool stable;

  /// Capture time in microseconds since the Unix epoch.
  final int timestampUs;
}

/// One sample of a waveform.
class TraceSample {
  /// Creates a trace sample.
  const TraceSample(this.timestampUs, this.value);

  /// Capture time in microseconds since the Unix epoch.
  final int timestampUs;

  /// Amplitude in arbitrary units (shape only).
  final double value;
}

/// One update from the SDK.
///
/// Rate fields hold the latest valid value and may be `null` while the SDK
/// is still collecting its window (12 s for pulse, 30 s for breathing,
/// 60 s for HRV). Trace lists contain only samples that are new since the
/// previous update, so you can append them straight to a chart buffer.
class SmartSpectraMetrics {
  /// Creates a metrics update.
  const SmartSpectraMetrics({
    this.pulseRate,
    this.breathingRate,
    this.hrv,
    this.expression,
    this.blinking,
    this.talking,
    this.newBlinks = 0,
    this.pulseTrace = const [],
    this.breathingTrace = const [],
    this.edaTrace = const [],
  });

  /// Parses the platform payload.
  factory SmartSpectraMetrics.fromMap(Map<Object?, Object?> map) {
    T? read<T>(String key, T Function(Map<Object?, Object?>) parse) {
      final value = map[key];
      return value is Map<Object?, Object?> ? parse(value) : null;
    }

    return SmartSpectraMetrics(
      pulseRate: read('pulseRate', Reading.fromMap),
      breathingRate: read('breathingRate', Reading.fromMap),
      hrv: read('hrv', HrvReading.fromMap),
      expression: read('expression', ExpressionReading.fromMap),
      blinking: read('blinking', Detection.fromMap),
      talking: read('talking', Detection.fromMap),
      newBlinks: map['newBlinks'] is num ? (map['newBlinks'] as num).toInt() : 0,
      pulseTrace: _trace(map['pulseTrace']),
      breathingTrace: _trace(map['breathingTrace']),
      edaTrace: _trace(map['edaTrace']),
    );
  }

  static List<TraceSample> _trace(Object? raw) {
    if (raw is! Map<Object?, Object?>) return const [];
    final times = (raw['t'] as List<Object?>?) ?? const [];
    final values = (raw['v'] as List<Object?>?) ?? const [];
    final length = times.length < values.length ? times.length : values.length;
    return [
      for (var i = 0; i < length; i++) TraceSample(asInt(times[i]), asDouble(values[i]) ?? 0),
    ];
  }

  /// Pulse rate in beats per minute (12-second average). Valid range 40–110.
  final Reading? pulseRate;

  /// Breathing rate in breaths per minute (30-second average).
  final Reading? breathingRate;

  /// Heart-rate variability (60-second window).
  final HrvReading? hrv;

  /// Facial expression probabilities. Requires [SmartSpectraMetric.expressions].
  final ExpressionReading? expression;

  /// Latest blink state (eyes closed or open). Requires [SmartSpectraMetric.blinking].
  ///
  /// To count blinks, add up [newBlinks] instead: one update can contain
  /// several blinks, and only the latest state is shown here.
  final Detection? blinking;

  /// Blinks that started since the previous update. Sum this to count blinks.
  /// Requires [SmartSpectraMetric.blinking].
  final int newBlinks;

  /// Talking detection. Requires [SmartSpectraMetric.talking].
  final Detection? talking;

  /// New samples of the relative arterial-pressure (pulse) waveform.
  /// This is waveform shape only, not a blood-pressure measurement.
  final List<TraceSample> pulseTrace;

  /// New samples of the upper (chest) breathing waveform.
  final List<TraceSample> breathingTrace;

  /// New samples of the EDA proxy trace. Requires [SmartSpectraMetric.eda].
  final List<TraceSample> edaTrace;
}
