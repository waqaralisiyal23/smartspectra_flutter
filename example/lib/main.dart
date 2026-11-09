import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartspectra_flutter/smartspectra_flutter.dart';

/// Pass your key with:
/// flutter run --dart-define-from-file=api_keys.json
///   (copy api_keys.example.json to api_keys.json and paste your key)
const _apiKey = String.fromEnvironment('SMARTSPECTRA_API_KEY');

void main() => runApp(const LiveVitalsApp());

class LiveVitalsApp extends StatelessWidget {
  const LiveVitalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartSpectra Live Vitals',
      theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      home: const LiveVitalsPage(),
    );
  }
}

class LiveVitalsPage extends StatefulWidget {
  const LiveVitalsPage({super.key});

  @override
  State<LiveVitalsPage> createState() => _LiveVitalsPageState();
}

class _LiveVitalsPageState extends State<LiveVitalsPage> {
  final _spectra = SmartSpectra.instance;
  final _subscriptions = <StreamSubscription<Object?>>[];

  ProcessingStatus _status = ProcessingStatus.idle;
  String _hint = '';
  String? _error;
  Reading? _pulse;
  Reading? _breathing;
  HrvReading? _hrv;
  ExpressionReading? _expression;
  int _blinks = 0;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(_spectra.status.listen((s) => setState(() => _status = s)))
      ..add(_spectra.validation.listen((v) => setState(() => _hint = v.isOk ? '' : v.hint)))
      ..add(_spectra.errors.listen((e) => setState(() => _error = e.message)))
      ..add(_spectra.metrics.listen(_onMetrics));
  }

  void _onMetrics(SmartSpectraMetrics m) {
    setState(() {
      _pulse = m.pulseRate ?? _pulse;
      _breathing = m.breathingRate ?? _breathing;
      _hrv = m.hrv ?? _hrv;
      _expression = m.expression ?? _expression;
      _blinks += m.newBlinks;
    });
  }

  /// Start waits for the native preview, so the camera always has a view.
  bool _previewReady = false;

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_spectra.isActive) {
        await _spectra.stop();
        return;
      }
      if (_apiKey.isEmpty) {
        setState(() => _error = 'Missing API key: run with --dart-define-from-file=api_keys.json');
        return;
      }
      if (!await _spectra.requestCameraPermission()) {
        setState(() => _error = 'Camera permission is required.');
        return;
      }
      await _spectra.configure(const SmartSpectraConfig(
        apiKey: _apiKey,
        // Reach Presage even on networks whose DNS cannot find it.
        dnsFallback: true,
        metrics: {
          SmartSpectraMetric.breathing,
          SmartSpectraMetric.cardio,
          SmartSpectraMetric.expressions,
          SmartSpectraMetric.blinking,
        },
      ));
      setState(() {
        _pulse = _breathing = null;
        _hrv = null;
        _expression = null;
        _blinks = 0;
      });
      await _spectra.start();
    } on SmartSpectraException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _spectra.stop();
    super.dispose();
  }

  String _fmt(double? v, String unit) => v == null ? '--' : '${v.round()} $unit';

  @override
  Widget build(BuildContext context) {
    final busy = _status == ProcessingStatus.starting || _status == ProcessingStatus.stopping;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SmartSpectraPreview(
            onReady: () {
              if (mounted && !_previewReady) setState(() => _previewReady = true);
            },
          ),
          if (_hint.isNotEmpty && _spectra.isActive)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Chip(label: Text(_hint)),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              color: Colors.black.withValues(alpha: 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed columns, so values appearing never move other stats.
                  Row(
                    children: [
                      _Stat('Pulse', _fmt(_pulse?.value, 'bpm')),
                      _Stat('Breathing', _fmt(_breathing?.value, 'brpm')),
                      _Stat('HRV (RMSSD)', _fmt(_hrv != null && _hrv!.confidence > 0 ? _hrv!.rmssd : null, 'ms')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(flex: 1),
                      _Stat('Expression', _expression?.dominant?.name ?? '--', flex: 2),
                      _Stat('Blinks', '$_blinks', flex: 2),
                      const Spacer(flex: 1),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  FilledButton(
                    onPressed: busy || !_previewReady ? null : _toggle,
                    child: Text(_spectra.isActive ? 'Stop' : 'Start'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'For wellness and informational use only. Not a medical device.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One stat in a fixed-width column. The value shrinks to fit instead of
/// wrapping, and uses tabular digits so numbers don't jitter as they change.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.flex = 1});

  final String label;
  final String value;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
