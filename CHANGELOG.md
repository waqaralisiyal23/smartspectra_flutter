## 0.2.0

- `SmartSpectraPreview(onReady:)`: called once the native preview view exists
  and is attached to the SDK. Screens that mount the preview and start
  measuring at the same time can wait for it, so the camera never runs
  without a visible preview. Same on Android and iOS.
- Connectivity failures (for example `COULDNT_RESOLVE_HOST`, Android's
  `UnknownHostException`, iOS "hostname could not be found" or "offline") are
  now reported as `SmartSpectraErrorCode.networkError` and marked retryable,
  whatever code the SDK used. New `SmartSpectraException.fromNative` and
  `isConnectivityProblem`.
- `SmartSpectraConfig(dnsFallback: true)`: keeps Presage's service reachable
  when the network's DNS cannot find it (some home routers and ISPs). The
  SDK's own networking (libcurl, inside its native library) is pointed at a
  small loopback proxy in the app that tunnels only to `*.presagetech.com`,
  resolving with the phone's DNS first and DNS-over-HTTPS (1.1.1.1, then
  8.8.8.8) only when that fails. TLS stays end to end. Off by default; pure
  Dart, so identical on Android and iOS.
- iOS: after a failed start, `configure` no longer fails with "Select an
  input while SmartSpectra is stopped": the SDK is reset and the
  configuration applied again. Swift status values such as `error(...)` are
  now parsed instead of read as idle.
- Example: Start is enabled once the preview is ready; DNS fallback on.
- Tested on a physical iPhone (iOS 27), including the DNS fallback on a
  network whose DNS cannot resolve Presage, as well as Android (Galaxy S22).
- README: troubleshooting for iOS debug builds closing when the debugger
  disconnects (use `--profile`) and the SDK's duplicate-class warnings.
- New dependency: `ffi` (used to point the SDK's networking at the fallback
  proxy).

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
