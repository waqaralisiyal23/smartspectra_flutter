import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'errors.dart';
import 'models.dart';
import 'parse.dart';

/// Entry point to the SmartSpectra SDK.
///
/// The native SDK is a singleton, so this class is too: use
/// [SmartSpectra.instance].
///
/// Typical flow:
/// 1. [requestCameraPermission] after showing your own consent screen.
/// 2. [configure] with your API key and the metrics you need.
/// 3. Listen to [metrics], [status], [validation] and [errors].
/// 4. [start]; later [stop].
class SmartSpectra {
  SmartSpectra._();

  /// The shared instance.
  static final SmartSpectra instance = SmartSpectra._();

  static const MethodChannel _methods = MethodChannel('smartspectra_flutter/methods');
  static const EventChannel _events = EventChannel('smartspectra_flutter/events');

  final _metrics = StreamController<SmartSpectraMetrics>.broadcast();
  final _status = StreamController<ProcessingStatus>.broadcast();
  final _validation = StreamController<ValidationStatus>.broadcast();
  final _errors = StreamController<SmartSpectraException>.broadcast();

  StreamSubscription<Object?>? _subscription;
  ProcessingStatus _currentStatus = ProcessingStatus.idle;
  ValidationStatus? _currentValidation;

  /// Metric updates, at up to ~30 per second while running.
  Stream<SmartSpectraMetrics> get metrics {
    _ensureListening();
    return _metrics.stream;
  }

  /// Pipeline lifecycle changes.
  Stream<ProcessingStatus> get status {
    _ensureListening();
    return _status.stream;
  }

  /// Imaging guidance ("Too dark", "Face not centered", ...).
  Stream<ValidationStatus> get validation {
    _ensureListening();
    return _validation.stream;
  }

  /// Errors reported by the SDK while running.
  Stream<SmartSpectraException> get errors {
    _ensureListening();
    return _errors.stream;
  }

  /// The most recent [ProcessingStatus].
  ProcessingStatus get currentStatus => _currentStatus;

  /// The most recent [ValidationStatus], if any.
  ValidationStatus? get currentValidation => _currentValidation;

  /// Whether a measurement is starting or running.
  bool get isActive =>
      _currentStatus == ProcessingStatus.starting || _currentStatus == ProcessingStatus.running;

  /// Applies [config]. Call while stopped; changes take effect on the next
  /// [start].
  Future<void> configure(SmartSpectraConfig config) async {
    _ensureListening();
    await _invoke<void>('configure', config.toMap());
  }

  /// Whether camera permission is already granted.
  Future<bool> hasCameraPermission() async =>
      (await _invoke<bool>('hasCameraPermission')) ?? false;

  /// Shows the system camera-permission prompt if needed.
  ///
  /// Show your own explanation of what is measured and why before calling
  /// this. Returns `true` when permission is granted.
  Future<bool> requestCameraPermission() async =>
      (await _invoke<bool>('requestCameraPermission')) ?? false;

  /// Starts measuring. Completes when the pipeline is running.
  ///
  /// Throws [SmartSpectraException] on failure (for example, a bad API key).
  Future<void> start() async {
    _ensureListening();
    await _invoke<void>('start');
  }

  /// Stops measuring and releases the camera.
  Future<void> stop() => _invoke<void>('stop');

  /// Stops and clears measurement state. Use to recover from
  /// [ProcessingStatus.error].
  Future<void> reset() => _invoke<void>('reset');

  void _ensureListening() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) {
        if (error is PlatformException) {
          _errors.add(_fromPlatform(error));
        } else {
          debugPrint('smartspectra_flutter: event error $error');
        }
      },
    );
  }

  void _onEvent(Object? event) {
    if (event is! Map<Object?, Object?>) return;
    final data = event['data'];
    switch (event['type']) {
      case 'metrics':
        if (data is Map<Object?, Object?>) _metrics.add(SmartSpectraMetrics.fromMap(data));
      case 'status':
        _currentStatus = parseEnum(ProcessingStatus.values, data as String?, ProcessingStatus.idle);
        _status.add(_currentStatus);
      case 'validation':
        if (data is Map<Object?, Object?>) {
          final status = ValidationStatus.fromMap(data);
          _currentValidation = status;
          _validation.add(status);
        }
      case 'error':
        if (data is Map<Object?, Object?>) _errors.add(SmartSpectraException.fromMap(data));
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw _fromPlatform(e);
    }
  }

  SmartSpectraException _fromPlatform(PlatformException e) {
    final details = e.details;
    return SmartSpectraException(
      code: parseEnum(SmartSpectraErrorCode.values, e.code, SmartSpectraErrorCode.unknown),
      message: e.message ?? e.code,
      retryable: details is Map && details['retryable'] == true,
    );
  }
}
