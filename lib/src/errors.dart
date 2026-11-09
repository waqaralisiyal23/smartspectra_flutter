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
  factory SmartSpectraException.fromMap(Map<Object?, Object?> map) => SmartSpectraException.fromNative(
        code: map['code'] as String?,
        message: map['message'] as String?,
        retryable: (map['retryable'] as bool?) ?? false,
      );

  /// Builds an exception from a native error code and message.
  ///
  /// Failures to reach Presage's service, such as a DNS lookup failing
  /// (`COULDNT_RESOLVE_HOST`) or the phone being offline, are reported by
  /// the SDK under various codes. They all become
  /// [SmartSpectraErrorCode.networkError] here, retryable, so apps can show
  /// one "check your connection" message on both platforms.
  factory SmartSpectraException.fromNative({
    required String? code,
    required String? message,
    bool retryable = false,
  }) {
    final text = message ?? code ?? 'Unknown SmartSpectra error';
    if (isConnectivityProblem(text)) {
      return SmartSpectraException(
        code: SmartSpectraErrorCode.networkError,
        message: text,
        retryable: true,
      );
    }
    return SmartSpectraException(
      code: parseEnum(SmartSpectraErrorCode.values, code, SmartSpectraErrorCode.unknown),
      message: text,
      retryable: retryable,
    );
  }

  static final RegExp _connectivity = RegExp(
    [
      r"couldn'?t[ _]resolve[ _]host", // libcurl: COULDNT_RESOLVE_HOST
      r'could not resolve host',
      r'unable to resolve host', // Android: UnknownHostException
      r'unknownhostexception',
      r'hostname could not be found', // iOS: NSURLErrorCannotFindHost
      r'cannot find host',
      r"couldn'?t[ _]connect", // libcurl: COULDNT_CONNECT
      r'connect tunnel failed', // libcurl: the DNS fallback proxy could not reach Presage
      r'network is unreachable',
      r'internet connection appears to be offline', // iOS: NotConnectedToInternet
      r'not connected to the internet',
    ].join('|'),
    caseSensitive: false,
  );

  /// Whether [message] describes not reaching the network at all.
  static bool isConnectivityProblem(String message) => _connectivity.hasMatch(message);

  /// What went wrong.
  final SmartSpectraErrorCode code;

  /// Human-readable message from the SDK.
  final String message;

  /// Whether retrying the same operation may succeed.
  final bool retryable;

  @override
  String toString() => 'SmartSpectraException(${code.name}): $message';
}
