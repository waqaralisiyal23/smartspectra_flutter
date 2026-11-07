# smartspectra_flutter

Unofficial Flutter plugin for the [Presage SmartSpectra SDK](https://smartspectra.presagetech.com/).
Turn the phone camera into a contactless sensor for:

- **Pulse rate** (12 s average, 40–110 BPM) and the pulse waveform
- **Breathing rate** (30 s average, 5–40 breaths/min) and the chest waveform
- **Heart-rate variability**: RMSSD, SDNN, mean NN, Baevsky stress index (60 s window)
- **Facial expressions**: angry, contempt, disgust, fear, happy, neutral, sad, surprise
- **Blinking** and **talking** detection
- Live **imaging guidance** ("Too dark", "Face not centered", ...)

Works on **Android** and **iOS**. Frames are processed on the device.

> **Status (0.1.0):** tested end to end on a physical Android phone. The iOS
> side builds for device; on-device iOS testing is in progress.

> This is a community package. It is not made or endorsed by Presage Technologies.
> SmartSpectra is a trademark of Presage Technologies, Inc. The SDK itself is
> proprietary and governed by Presage's terms.

> **Wellness use only.** SDK metrics are for general wellness and informational
> purposes. They are not cleared for medical diagnosis or treatment.

## Requirements

| | Android | iOS |
|---|---|---|
| Flutter | 3.44+ | 3.44+ |
| Minimum OS | API 28 (Android 9) | iOS 17 |
| Build | compileSdk 36, AGP 8.10.1+, built-in Kotlin | Swift Package Manager (default in Flutter 3.44+) |
| Device | Physical device with a camera | Physical device (no Simulator) |

You also need a SmartSpectra API key: register at
[physiology.presagetech.com](https://physiology.presagetech.com/auth/register).

## Install

```sh
flutter pub add smartspectra_flutter
```

### Android

In `android/app/build.gradle.kts`:

```kotlin
android {
    compileSdk = 36
    defaultConfig {
        minSdk = 28
    }
}
```

The plugin uses Flutter's built-in Kotlin support, so it needs no extra Kotlin
setup. On Flutter 3.47+ you can turn it on for your app too with
`android.builtInKotlin=true` in `android/gradle.properties`.

The plugin adds the `CAMERA` and `INTERNET` permissions to your manifest.

### iOS

1. Use Swift Package Manager (default since Flutter 3.44). On older versions:
   `flutter config --enable-swift-package-manager`.
2. Set the deployment target to **iOS 17.0** in Xcode (Runner → General → Minimum Deployments).
3. Add a camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera measures pulse and breathing on this device. No video is recorded.</string>
```

## Usage

```dart
import 'package:smartspectra_flutter/smartspectra_flutter.dart';

final spectra = SmartSpectra.instance;

// 1. Explain what you measure, then ask for the camera.
final granted = await spectra.requestCameraPermission();

// 2. Configure.
await spectra.configure(const SmartSpectraConfig(
  apiKey: String.fromEnvironment('SMARTSPECTRA_API_KEY'),
  metrics: {
    SmartSpectraMetric.cardio,      // pulse, pulse waveform, HRV
    SmartSpectraMetric.breathing,   // breathing rate + waveform
    SmartSpectraMetric.expressions, // facial expressions
  },
));

// 3. Listen.
var blinks = 0;
spectra.metrics.listen((m) {
  final bpm = m.pulseRate?.value;
  final mood = m.expression?.dominant; // Expression.happy, ...
  blinks += m.newBlinks;               // needs SmartSpectraMetric.blinking
});
spectra.validation.listen((v) => print(v.hint)); // "Too dark"
spectra.status.listen((s) => print(s));          // ProcessingStatus.running
spectra.errors.listen((e) => print(e.code));     // SmartSpectraErrorCode.creditExhausted

// 4. Start / stop.
await spectra.start();
await spectra.stop();
```

Show the camera with `SmartSpectraPreview`. Put it on screen **before** calling
`start()`:

```dart
const SizedBox(height: 320, child: SmartSpectraPreview())
```

While nothing is being measured, the preview shows a black box instead of the
last camera frame. Pass your own with `SmartSpectraPreview(placeholder: ...)`.

### Reading the values

- Rate fields (`pulseRate`, `breathingRate`, `hrv`) are `null` until the SDK
  has collected enough frames. Keep the last value you received.
- Every reading carries `confidence` (0–100) and `stable`. Prefer `stable`
  values for decisions.
- HRV `confidence` stays 0 until a full 60 seconds of data is collected.
- Trace lists (`pulseTrace`, `breathingTrace`) contain only **new** samples
  in each update, ready to append to a chart.
- To count blinks, add up `newBlinks`. One update can contain several blinks,
  so watching `blinking.detected` alone misses fast ones.
- The pulse waveform is shape only. It is **not** a blood-pressure reading.

### Getting a good measurement

The SDK works best when the person sits still, the face and upper chest are
visible and well lit, and the camera is steady. Breathing needs a stable (not
handheld) camera and does not work while talking. Avoid flickering light such
as TV screens. Watch `validation` for live guidance.

### Lifecycle

- The plugin **stops the measurement automatically when the app leaves the
  screen**, so the camera never runs in the background. Call `start()` again
  when the user comes back.
- While a measurement is running, the plugin keeps the screen awake.
- Still call `stop()` when your measuring screen goes away.

### Troubleshooting

- **`Could not resolve host: ...presagetech.com`** when starting: the device's
  network DNS cannot look up Presage's servers (some home routers and ISPs).
  Switch networks or set a public DNS on the device, for example Android
  Private DNS `one.one.one.one`.

## Privacy and telemetry

- Video frames are processed on the device. The SDK contacts Presage to
  validate the API key and load models.
- The SDK can send an aggregate, anonymous diagnostic summary per session
  (SDK version, device model, frame-rate statistics; never video or measured
  values). This plugin turns it **off by default**; opt in with
  `SmartSpectraConfig(enableTelemetry: true)`.
  See [SDK Telemetry & Privacy](https://smartspectra.presagetech.com/docs/telemetry-and-privacy/).
- This plugin does not use the SDK's LLM Insights feature.
- Disclose camera use and data handling to your users, and complete the App
  Store / Play Store data declarations for your app.

## Example

The [example](example/) app shows live pulse, breathing, HRV, expression and
blink count. To run it:

```sh
cd example
./setup.sh                               # generates android/ and ios/ (macOS)
cp api_keys.example.json api_keys.json   # then paste your API key
flutter run --dart-define-from-file=api_keys.json
```

`api_keys.json` is git-ignored, so your key stays out of the repository.

## Not supported yet

Custom camera frames (`useCustomInput`), face landmarks, OAuth login, LLM
Insights, and desktop platforms. Contributions are welcome.

## License

MIT for this plugin's code. The SmartSpectra SDK it depends on is proprietary;
see Presage's license terms.
