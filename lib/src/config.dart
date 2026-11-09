/// Groups of measurements the SDK can compute.
///
/// Request only what you need: each group costs processing time.
enum SmartSpectraMetric {
  /// Breathing rate and the upper (chest) breathing waveform.
  breathing,

  /// Pulse rate, the relative arterial-pressure waveform and HRV.
  cardio,

  /// Facial expression probabilities (angry, happy, sad, ...).
  expressions,

  /// Blink detection.
  blinking,

  /// Talking detection.
  talking,

  /// Electrodermal-activity proxy trace (experimental in the SDK).
  eda,
}

/// Which camera the SDK should open.
enum SmartSpectraCamera {
  /// The SDK default (prefers the front camera when available).
  defaultCamera,

  /// Front ("selfie") camera.
  front,

  /// Rear camera.
  back,
}

/// Configuration passed to [SmartSpectra.configure].
class SmartSpectraConfig {
  /// Creates a configuration.
  const SmartSpectraConfig({
    required this.apiKey,
    this.metrics = const {SmartSpectraMetric.breathing, SmartSpectraMetric.cardio},
    this.camera = SmartSpectraCamera.front,
    this.enableTelemetry = false,
    this.previewEnabled = true,
    this.dnsFallback = false,
  });

  /// Your API key from https://physiology.presagetech.com.
  ///
  /// Do not hard-code production keys in source control; pass them with
  /// `--dart-define` or fetch them from your backend.
  final String apiKey;

  /// Measurements to compute. Defaults to breathing + cardio.
  final Set<SmartSpectraMetric> metrics;

  /// Camera to use.
  final SmartSpectraCamera camera;

  /// Whether the SDK may send its aggregate, anonymous diagnostic summary
  /// (SDK version, device model, frame-rate stats; never video or measured
  /// values). The SDK defaults this to `true`; this plugin defaults it to
  /// `false` so apps opt in explicitly.
  final bool enableTelemetry;

  /// Whether a [SmartSpectraPreview] will be shown. On iOS this turns on the
  /// SDK's preview image output; turn it off for headless measurement.
  final bool previewEnabled;

  /// Keeps Presage's service reachable when the network's DNS cannot find it
  /// (some home routers and ISPs), on Android and iOS.
  ///
  /// The SDK connects through a small proxy inside your app, on the phone's
  /// loopback interface, that only tunnels to `*.presagetech.com`. It looks
  /// the server up with the phone's DNS first and, only when that fails,
  /// asks Cloudflare (1.1.1.1) or Google (8.8.8.8) over HTTPS, which tells
  /// them the hostname being looked up. TLS still runs end to end between
  /// the SDK and Presage: the proxy never sees the content. Off by default.
  final bool dnsFallback;

  /// Serializes the configuration for the platform channel.
  Map<String, Object?> toMap() => {
        'apiKey': apiKey,
        'metrics': metrics.map((m) => m.name).toList(),
        'camera': camera.name,
        'enableTelemetry': enableTelemetry,
        'previewEnabled': previewEnabled,
      };
}
