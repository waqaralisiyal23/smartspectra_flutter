/// Unofficial Flutter plugin for the Presage SmartSpectra SDK.
///
/// Measure pulse rate, breathing rate, heart-rate variability, blinking,
/// talking and facial expressions from the phone camera.
///
/// ```dart
/// final spectra = SmartSpectra.instance;
/// await spectra.configure(const SmartSpectraConfig(apiKey: 'YOUR_KEY'));
/// spectra.metrics.listen((m) => print(m.pulseRate?.value));
/// await spectra.start();
/// ```
library;

export 'src/config.dart';
export 'src/errors.dart';
export 'src/models.dart';
export 'src/preview.dart';
export 'src/smartspectra.dart';
