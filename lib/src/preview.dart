import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'smartspectra.dart';

/// Live camera preview for the running SmartSpectra measurement.
///
/// Put it on screen **before** calling `SmartSpectra.instance.start()` so the
/// SDK can attach its camera output to it. The preview fills its box and
/// crops to cover, like `BoxFit.cover`.
///
/// While no measurement is running, [placeholder] is shown on top, so the
/// last camera frame never stays frozen on screen after `stop()`.
///
/// When the preview is mounted in the same frame as `start()` (a screen that
/// starts measuring as it opens), wait for [onReady] before calling
/// `start()`: on Android the native view hands its surface to the SDK only
/// once it exists, and a measurement started earlier runs without a visible
/// preview.
///
/// On Android this hosts a CameraX `PreviewView`; on iOS it shows the SDK's
/// image output (requires `SmartSpectraConfig.previewEnabled`).
class SmartSpectraPreview extends StatefulWidget {
  /// Creates a preview.
  const SmartSpectraPreview({super.key, this.placeholder, this.onReady});

  /// Shown while no measurement is running. Defaults to a black box.
  final Widget? placeholder;

  /// Called once the native preview view exists and is attached to the SDK,
  /// so `start()` will show the camera in it. Called again if the native view
  /// is re-created. Same on Android and iOS.
  final VoidCallback? onReady;

  @override
  State<SmartSpectraPreview> createState() => _SmartSpectraPreviewState();
}

class _SmartSpectraPreviewState extends State<SmartSpectraPreview> {
  static const String _viewType = 'smartspectra_flutter/preview';

  final _spectra = SmartSpectra.instance;
  StreamSubscription<ProcessingStatus>? _subscription;
  late bool _live = _spectra.currentStatus == ProcessingStatus.running;

  @override
  void initState() {
    super.initState();
    _subscription = _spectra.status.listen((status) {
      // Only reveal the camera once frames are flowing, and hide it as soon
      // as the measurement winds down.
      final live = status == ProcessingStatus.running;
      if (live != _live && mounted) setState(() => _live = live);
    });
  }

  // The native view registers itself with the SDK while it is created, so
  // by now `start()` will use it.
  void _onCreated(int _) {
    if (mounted) widget.onReady?.call();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget camera;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        camera = AndroidView(
          viewType: _viewType,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onCreated,
        );
      case TargetPlatform.iOS:
        camera = UiKitView(
          viewType: _viewType,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onCreated,
        );
      default:
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'SmartSpectra preview is only available on Android and iOS',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        );
    }
    // The native view stays mounted so the SDK can always attach to it;
    // the placeholder simply covers it while idle.
    return Stack(
      fit: StackFit.expand,
      children: [
        camera,
        if (!_live) widget.placeholder ?? const ColoredBox(color: Colors.black),
      ],
    );
  }
}
