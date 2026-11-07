## 0.1.0

- Initial release.
- Android (SmartSpectra SDK 3.4.0) and iOS (SmartSpectra Swift SDK 3.4.0, via Swift Package Manager).
- Pulse rate, breathing rate, HRV, facial expressions, blinking, talking and EDA streams.
- Pulse and breathing waveforms delivered as incremental samples.
- Processing status, validation hints and typed errors.
- `SmartSpectraPreview` camera preview widget.
- Camera permission helpers.
- Telemetry off by default.
- Measuring stops automatically when the app leaves the screen, so the camera never runs in the background.
- The screen stays awake while a measurement is running.
- `SmartSpectraMetrics.newBlinks`: counts every blink in an update, so fast blinks are not missed.
- `SmartSpectraPreview` covers the camera with a placeholder while not measuring, so the last frame never stays frozen after `stop()`.
- Uses Flutter's built-in Kotlin; requires Flutter 3.44+ / Dart 3.12+.
- Tested on a physical Android phone. iOS builds for device; on-device iOS testing in progress.
