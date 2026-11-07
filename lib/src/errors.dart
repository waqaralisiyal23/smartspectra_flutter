import 'parse.dart';

/// Error codes reported by the SmartSpectra SDK.
enum SmartSpectraErrorCode {
  /// The call was made in the wrong state (for example, `start` while running).
  invalidState,

  /// The API key or OAuth setup was rejected.
  authenticationFailed,

  /// The configuration could not be applied.
  configurationFailed,

  /// The account has no measurement credits left.
  creditExhausted,

  /// The SDK could not reach Presage's service.
  networkError,

  /// Presage's service returned an error.
  serverError,

  /// The camera is unavailable or camera permission was denied.
  inputUnavailable,

  /// Processing failed on device.
  processingFailed,

  /// A frame could not be converted.
  frameConversionFailed,

  /// Frame timestamps were not increasing.
  nonMonotonicTimestamp,

  /// Frames stopped arriving for too long.
  timestampGap,

  /// An error this plugin version does not know about.
  unknown,
}

/// An error raised by the SDK, delivered on [SmartSpectra.errors] or thrown
/// from [SmartSpectra.start] / [SmartSpectra.stop].
class SmartSpectraException implements Exception {
  /// Creates an exception.
  const SmartSpectraException({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  /// Parses the platform payload.
  factory SmartSpectraException.fromMap(Map<Object?, Object?> map) {
    return SmartSpectraException(
      code: parseEnum(
        SmartSpectraErrorCode.values,
        map['code'] as String?,
        SmartSpectraErrorCode.unknown,
      ),
      message: (map['message'] as String?) ?? 'Unknown SmartSpectra error',
      retryable: (map['retryable'] as bool?) ?? false,
    );
  }

  /// What went wrong.
  final SmartSpectraErrorCode code;

  /// Human-readable message from the SDK.
  final String message;

  /// Whether retrying the same operation may succeed.
  final bool retryable;

  @override
  String toString() => 'SmartSpectraException(${code.name}): $message';
}
