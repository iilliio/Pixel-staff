import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:record/record.dart';

enum VisualMode { classic, lissajous, radialBars }

class FourierArtPage extends StatefulWidget {
  const FourierArtPage({super.key});

  @override
  State<FourierArtPage> createState() => _FourierArtPageState();
}

class _FourierArtPageState extends State<FourierArtPage>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;
  final List<double> _sampleBuffer = <double>[];

  // Audio features (smoothed 0..1)
  double _amplitude = 0.0; // overall loudness
  double _low = 0.0; // ~60-200 Hz
  double _mid = 0.0; // ~400-2k Hz
  double _high = 0.0; // ~3k-8k Hz

  // Expanded features/mappings
  double _centroid = 0.0; // 0..1 spectral brightness
  double _rolloff = 0.0; // 0..1 energy rolloff point
  double _flux = 0.0; // spectral flux (0..~1)
  double _onsetPulse = 0.0; // decaying pulse on onsets
  double _bpm = 0.0; // estimated tempo
  double _beatPulse = 0.0; // decaying pulse on beat grid
  DateTime _lastOnsetAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastBeatAnchor = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _onsetTimes = <DateTime>[]; // recent onsets
  List<double> _prevSpecFeat = <double>[]; // previous spectrum for flux
  final List<double> _fluxHistory = <double>[]; // recent fluxes for threshold
  static const int _fluxHistMax = 48; // ~0.75s at 16ms
  List<double> _chroma = List<double>.filled(12, 0.0);
  double _keyHue = 0.0; // degrees 0..360
  double _keyHueStrength = 0.0; // 0..1
  double _zcr = 0.0; // zero-crossing rate proxy for noisiness
  double _flatness = 0.0; // spectral flatness 0..1

  // User-configurable
  int _numHarmonics = 7;
  bool _audioReactive = true;
  double _lowInfluence = 1.0;
  double _midInfluence = 0.5;
  double _highInfluence = 1.0;
  double _reactStrength = 1.9; // overall morph intensity
  double _reactSpeed = 2.8; // overall response speed (higher = faster)
  bool _cosOnly = false; // simple symmetry switch: sin terms set to 0 when true
  bool _fillShape = true;
  double _strokeWidth = 1.0;
  int _symmetryOrder = 6; // k-fold rotational symmetry (classic mode)
  VisualMode _mode = VisualMode.classic;
  int _resolution = 150; // target result resolution in px/bins
  bool _pixelGrid = true; // show pixelated result at chosen resolution

  // Fourier coefficients (x(t) = Σ [a_k cos(k t + φ_k) + b_k sin(k t + φ_k)])
  //                        y(t) = Σ [c_k cos(k t + ψ_k) + d_k sin(k t + ψ_k)])
  late List<double> _a; // cos for x
  late List<double> _b; // sin for x
  late List<double> _c; // cos for y
  late List<double> _d; // sin for y
  // Baseline (unmorphed) coefficient sets to morph around
  late List<double> _aBase;
  late List<double> _bBase;
  late List<double> _cBase;
  late List<double> _dBase;
  late List<double> _phi; // phase for x
  late List<double> _psi; // phase for y

  // Animation ticker
  late final Ticker _ticker;
  double _time = 0.0;
  DateTime _lastTick = DateTime.now();
  bool _micGranted = false;
  bool _streamActive = false;
  DateTime _lastSignalAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _meterLevel = 0.0; // fast meter level 0..1
  ui.Image? _classicImage; // offscreen raster at resolution x resolution
  bool _isRendering = false;
  DateTime _lastRenderAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Noise gate and filtering
  double _noiseRms = 0.01; // adaptive baseline in raw RMS domain
  double _lowFloor = 0.0;
  double _midFloor = 0.0;
  double _highFloor = 0.0;
  bool _gateOpen = false;
  double _gate = 0.0; // 0..1 smoothing for open/close
  double _gateSensitivity = 1.3; // higher = opens easier
  List<double> _specSmooth = <double>[]; // smoothed spectrum for radial bars
  // Background spectrum filter (learn ambient per bin and subtract)
  bool _bgFilterEnabled = true;
  double _bgMargin = 0.15; // subtract background * (1 + margin)
  final double _bgLearnRateClosed = 0.05; // when gate closed
  final double _bgLearnRateOpen =
      0.0; // when gate open (no learning by default)
  List<double> _bgSpec = <double>[]; // ambient estimate per bin (0..1)

  // Smoothly changing color palette
  final int _paletteSize = 9;
  late List<HSVColor> _palette;
  late List<HSVColor> _paletteTarget;
  double _paletteTimer = 0.0;
  double _paletteCycleSec = 10.0;
  double _paletteLerpFactor = 0.12;
  // Auto-randomize
  bool _autoRandomize = false;
  double _autoIntervalSec = 4.0;
  double _autoTimer = 0.0;

  // Analysis settings
  static const int _sampleRate = 44100;
  static const int _fftSize = 1024; // analysis window
  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initCoefficients(_numHarmonics);
    _initPalette();
    _lastTick = DateTime.now();
    _ticker = createTicker((Duration elapsed) {
      final DateTime now = DateTime.now();
      final double dt = now.difference(_lastTick).inMilliseconds / 1000.0;
      _lastTick = now;
      _time = elapsed.inMilliseconds / 1000.0;
      _stepMorph(dt);
      _stepPalette(dt);
      // Decay transient pulses
      _onsetPulse *= math.exp(-dt / 0.10); // ~100ms half-life
      _beatPulse *= math.exp(-dt / 0.18); // ~180ms half-life
      // Offscreen render for Classic mode (enforce exact resolution)
      _maybeRenderClassicImage();
      // Auto-randomize
      if (_autoRandomize) {
        _autoTimer += dt;
        if (_autoTimer >= _autoIntervalSec) {
          _autoTimer = 0.0;
          _setNewBaseRandom(_numHarmonics);
        }
      }
      if (mounted) setState(() {});
    });
    _ticker.start();
    _startAudio();
  }

  void _maybeRenderClassicImage() {
    if (_mode != VisualMode.classic) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastRenderAt).inMilliseconds < 33) return; // ~30 fps
    if (_isRendering) return;
    _isRendering = true;
    _lastRenderAt = now;
    final int size = _resolution.clamp(10, 512);
    _renderClassicToImage(size).whenComplete(() {
      _isRendering = false;
    });
  }

  Future<void> _renderClassicToImage(int size) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas c = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );
    // Render same as painter but in a size x size square
    final double minDim = size.toDouble();
    c.translate(minDim / 2, minDim / 2);

    // Compute one fundamental loop
    final int baseSteps = math.max(
      40,
      size * 10 ~/ math.max(1, _symmetryOrder),
    );
    final double dt = (2 * math.pi) / (baseSteps - 1);
    final List<Offset> basePoints = <Offset>[];
    double maxAbs = 1e-6;
    for (int i = 0; i < baseSteps; i++) {
      final double tt = dt * i;
      double x = 0.0;
      double y = 0.0;
      for (int k = 0; k < _a.length; k++) {
        final double kk = (k + 1).toDouble();
        final double phaseX =
            _phi[k] +
            kk * (_time * 0.6 + (_audioReactive ? _amplitude * 0.4 : 0.0));
        final double phaseY =
            _psi[k] +
            kk * (_time * 0.6 + (_audioReactive ? _amplitude * 0.4 : 0.0));
        x +=
            _a[k] * math.cos(kk * tt + phaseX) +
            _b[k] * math.sin(kk * tt + phaseX);
        y +=
            _c[k] * math.cos(kk * tt + phaseY) +
            _d[k] * math.sin(kk * tt + phaseY);
      }
      basePoints.add(Offset(x, y));
      maxAbs = math.max(maxAbs, math.max(x.abs(), y.abs()));
    }
    // Size reacts to loudness and beat pulse
    final double behaveScale = (1.0 + 0.12 * (_amplitude + 0.6 * _beatPulse));
    final double scale = (minDim * 0.42) / maxAbs * behaveScale;
    for (int i = 0; i < basePoints.length; i++) {
      basePoints[i] = basePoints[i] * scale;
    }
    final Path path = Path();
    for (int s = 0; s < math.max(1, _symmetryOrder); s++) {
      final double angle = (2 * math.pi * s) / math.max(1, _symmetryOrder);
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      for (int i = 0; i < basePoints.length; i++) {
        final Offset p = basePoints[i];
        final Offset pr = Offset(
          p.dx * cosA - p.dy * sinA,
          p.dx * sinA + p.dy * cosA,
        );
        if (s == 0 && i == 0) {
          path.moveTo(pr.dx, pr.dy);
        } else {
          path.lineTo(pr.dx, pr.dy);
        }
      }
      path.close();
    }
    path.fillType = PathFillType.evenOdd;

    if (_fillShape) {
      _drawOverlappedFill(c, path, minDim, _time);
    }
    if (_strokeWidth > 0.0) {
      final Paint stroke =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (_strokeWidth + 2.0 * _onsetPulse)
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = _strokeColor(
              hueBase: _currentHueBase(),
              amp: _amplitude,
              centroid: _centroid,
              beatPulse: _beatPulse,
            );
      c.drawPath(path, stroke);
    }

    final ui.Image img = await recorder.endRecording().toImage(size, size);
    if (mounted) {
      setState(() {
        _classicImage = img;
      });
    } else {
      img.dispose();
    }
  }

  void _initPalette() {
    final math.Random rand = math.Random();
    final double baseHue = rand.nextDouble() * 360.0;
    final double hueStep = 360.0 / _paletteSize;
    _palette = List<HSVColor>.generate(_paletteSize, (int i) {
      final double jitter =
          (rand.nextDouble() - 0.5) * hueStep * 0.4; // ±20% of step
      final double hue = (baseHue + i * hueStep + jitter) % 360.0;
      final double sat = 0.75 + rand.nextDouble() * 0.25; // 0.75..1.0
      final double val = 0.9 + rand.nextDouble() * 0.1; // 0.9..1.0
      return HSVColor.fromAHSV(1.0, hue, sat, val);
    });
    final double targetBaseHue = rand.nextDouble() * 360.0;
    _paletteTarget = List<HSVColor>.generate(_paletteSize, (int i) {
      final double jitter =
          (rand.nextDouble() - 0.5) * hueStep * 0.6; // ±30% of step
      final double hue = (targetBaseHue + i * hueStep + jitter) % 360.0;
      final double sat = 0.65 + rand.nextDouble() * 0.35; // 0.65..1.0
      final double val = 0.85 + rand.nextDouble() * 0.15; // 0.85..1.0
      return HSVColor.fromAHSV(1.0, hue, sat, val);
    });
    _paletteCycleSec = 6.0 + rand.nextDouble() * 12.0; // 6..18s
    _paletteLerpFactor = 0.08 + rand.nextDouble() * 0.24; // 0.08..0.32
  }

  void _stepPalette(double dt) {
    _paletteTimer += dt;
    final double cycle = _paletteCycleSec; // seconds per palette drift
    if (_paletteTimer > cycle) {
      _paletteTimer = 0.0;
      final math.Random rand = math.Random();
      final double baseHue = rand.nextDouble() * 360.0;
      final double hueStep = 360.0 / _paletteSize;
      _paletteTarget = List<HSVColor>.generate(_paletteSize, (int i) {
        final double jitter =
            (rand.nextDouble() - 0.5) * hueStep * 0.6; // ±30% of step
        final double hue = (baseHue + i * hueStep + jitter) % 360.0;
        final double sat = 0.65 + rand.nextDouble() * 0.35; // 0.65..1.0
        final double val = 0.85 + rand.nextDouble() * 0.15; // 0.85..1.0
        return HSVColor.fromAHSV(1.0, hue, sat, val);
      });
      _paletteCycleSec = 6.0 + rand.nextDouble() * 12.0; // randomize next cycle
      _paletteLerpFactor =
          0.08 + rand.nextDouble() * 0.24; // randomize lerp speed
    }
    final double t = (_paletteTimer / cycle).clamp(0.0, 1.0);
    for (int i = 0; i < _palette.length; i++) {
      final double lerpAmt = (t * _paletteLerpFactor).clamp(0.0, 1.0);
      _palette[i] =
          HSVColor.lerp(_palette[i], _paletteTarget[i], lerpAmt) ?? _palette[i];
    }
  }

  void _drawOverlappedFill(Canvas c, Path basePath, double minDim, double t) {
    final int layers = (_symmetryOrder * 2).clamp(2, 24);
    for (int i = 0; i < layers; i++) {
      final double angle = (2 * math.pi * i) / layers;
      final Path p = basePath.transform(Matrix4.rotationZ(angle).storage);
      final HSVColor color = _palette[i % _palette.length];
      // Boost brightness with loudness and beat, desaturate with flatness/noise
      final double satMod = (color.saturation * (1.0 - 0.25 * _flatness)).clamp(
        0.0,
        1.0,
      );
      final HSVColor bright = color
          .withSaturation(satMod)
          .withValue(
            (0.9 + 0.1 * (_amplitude + 0.6 * _beatPulse)).clamp(0.0, 1.0),
          );
      final Color c0 = bright.toColor().withOpacity(
        0.35 + 0.35 * (0.5 + 0.5 * math.sin(t + i)),
      );
      final Paint fill =
          Paint()
            ..style = PaintingStyle.fill
            ..color = c0; // solid fill color, no gradient
      c.drawPath(p, fill);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _stopAudio();
    super.dispose();
  }

  void _initCoefficients(int n) {
    final math.Random random = math.Random();
    _aBase = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    _bBase = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    _cBase = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    _dBase = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    _a = List<double>.from(_aBase);
    _b = List<double>.from(_bBase);
    _c = List<double>.from(_cBase);
    _d = List<double>.from(_dBase);
    _phi = List<double>.generate(
      n,
      (int i) => random.nextDouble() * 2 * math.pi,
    );
    _psi = List<double>.generate(
      n,
      (int i) => random.nextDouble() * 2 * math.pi,
    );
    if (_cosOnly) {
      for (int i = 0; i < n; i++) {
        _bBase[i] = 0.0;
        _dBase[i] = 0.0;
        _b[i] = 0.0;
        _d[i] = 0.0;
      }
    }
  }

  void _stepMorph(double dt) {
    if (!_audioReactive) return;
    final int n = _a.length;
    if (n == 0) return;
    final double low = _low * _lowInfluence;
    final double mid = _mid * _midInfluence;
    final double high = _high * _highInfluence;
    final double amp = _amplitude;
    final double strength = _reactStrength.clamp(0.0, 2.0);
    final double speed = (0.8 + _reactSpeed).clamp(0.2, 3.0);
    // Morph duration derived from interval: if interval is X seconds,
    // target morph duration is X seconds (~99% completion).
    final double desiredDurationSec = _autoIntervalSec.clamp(0.1, 120.0);
    // Make transitions much slower: reach ~99% over 5× the chosen interval
    double tau = (desiredDurationSec * 5.0) / 4.605170186; // 99% at duration
    tau = tau / speed; // respect Speed slider

    // Per-harmonic spectral weights (sample spectrum)
    final List<double> spec = _computeSpectrumSnapshot(
      bins: math.max(12, n * 2),
    );

    for (int k = 0; k < n; k++) {
      final double pos = n == 1 ? 0.0 : (k / (n - 1));
      final double wLow = 1.0 - pos;
      final double wMid = 1.0 - (pos - 0.5).abs() * 2.0;
      final double wHigh = pos;
      // Map spectrum bins onto harmonics (wrap index)
      final int si = (k * 2) % spec.length;
      final double sA = spec[si];
      final double sB = spec[(si + 1) % spec.length];
      // Separate influences for a/b/c/d
      final double morphA =
          strength * (1.2 * low * wLow + 0.3 * sA + 0.1 * amp);
      final double morphB =
          strength * (1.2 * mid * wMid + 0.3 * sB + 0.1 * amp);
      final double morphC =
          strength * (1.2 * high * wHigh + 0.3 * sA + 0.1 * amp);
      final double morphD =
          strength * (0.8 * (low + high) * 0.5 + 0.3 * sB + 0.2 * amp);

      final double aScale = 1.0 + 1.6 * morphA;
      final double bScale = 1.0 + 1.6 * morphB;
      final double cScale = 1.0 + 1.6 * morphC;
      final double dScale = 1.0 + 1.6 * morphD;
      final double biasA = 0.12 * morphA * (0.5 - (pos - 0.5));
      final double biasB = -0.12 * morphB * (0.5 - (pos - 0.5));
      final double biasC = -0.12 * morphC * (pos - 0.5);
      final double biasD = 0.12 * morphD * (pos - 0.5);
      final double aTarget = _aBase[k] * aScale + biasA;
      final double bTarget = _cosOnly ? 0.0 : (_bBase[k] * bScale + biasB);
      final double cTarget = _cBase[k] * cScale + biasC;
      final double dTarget = _cosOnly ? 0.0 : (_dBase[k] * dScale + biasD);

      // Slow interpolation (10x slower than before)
      final double alpha = (1.0 - math.exp(-dt / tau)).clamp(0.0, 1.0);
      _a[k] = _a[k] + (aTarget - _a[k]) * alpha;
      _b[k] = _b[k] + (bTarget - _b[k]) * alpha;
      _c[k] = _c[k] + (cTarget - _c[k]) * alpha;
      _d[k] = _d[k] + (dTarget - _d[k]) * alpha;

      final double kk = (k + 1).toDouble();
      final double phaseSpeed =
          (0.35 * low * wLow +
              0.55 * mid * wMid +
              0.8 * high * wHigh +
              0.3 * amp) *
          strength *
          speed;
      _phi[k] += kk * phaseSpeed * dt;
      _psi[k] += kk * phaseSpeed * dt;
    }
  }

  Future<void> _startAudio() async {
    try {
      bool permitted = await _recorder.hasPermission();
      _micGranted = permitted;
      if (!permitted) {
        if (mounted) setState(() {});
        return;
      }

      await _recorder.stop();
      final Stream<Uint8List> stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: _sampleRate,
        ),
      );

      _audioSub = stream.listen((Uint8List chunk) {
        _appendPcmChunk(chunk);
        _analyzeIfDue();
        _streamActive = true;
        if (_sampleBuffer.isNotEmpty) {
          _lastSignalAt = DateTime.now();
        }
      });
    } catch (_) {
      // Swallow errors to keep page usable without mic
    }
  }

  Future<void> _stopAudio() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder.stop();
  }

  void _appendPcmChunk(Uint8List bytes) {
    // Convert incoming PCM to normalized doubles (-1..1)
    if (Platform.isMacOS) {
      // macOS often delivers Float32 IEEE PCM
      if (bytes.length >= 4) {
        final ByteData bd = ByteData.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.length,
        );
        for (int i = 0; i + 3 < bytes.length; i += 4) {
          final double v = bd.getFloat32(i, Endian.little);
          _sampleBuffer.add(v.clamp(-1.0, 1.0));
        }
      }
    } else {
      // Default: 16-bit little-endian PCM
      for (int i = 0; i + 1 < bytes.length; i += 2) {
        final int lo = bytes[i];
        final int hi = bytes[i + 1];
        int val = (hi << 8) | lo;
        if (val & 0x8000 != 0) {
          val = val - 0x10000;
        }
        _sampleBuffer.add(val / 32768.0);
      }
    }
    // Keep last ~4096 samples
    if (_sampleBuffer.length > 4096) {
      _sampleBuffer.removeRange(0, _sampleBuffer.length - 4096);
    }
  }

  bool get _hasRecentSignal =>
      DateTime.now().difference(_lastSignalAt).inMilliseconds < 500;

  // _openSoundSettings removed per user request

  void _analyzeIfDue() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastAnalysisAt).inMilliseconds < 16) {
      return; // ~30 fps analysis
    }
    _lastAnalysisAt = now;
    if (_sampleBuffer.length < _fftSize) return;

    final List<double> window = _sampleBuffer.sublist(
      _sampleBuffer.length - _fftSize,
    );
    // Remove DC offset to reduce low-frequency bias
    final List<double> samples = List<double>.from(window);
    double mean = 0.0;
    for (int i = 0; i < samples.length; i++) {
      mean += samples[i];
    }
    mean /= samples.length;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = samples[i] - mean;
    }

    // Overall loudness (RMS)
    double sumSq = 0.0;
    for (int i = 0; i < samples.length; i++) {
      final double s = samples[i];
      sumSq += s * s;
    }
    final double rms = math.sqrt(sumSq / samples.length);
    // Adaptive noise gate with hysteresis on raw RMS
    final double base = _noiseRms.clamp(1e-6, 1.0);
    final double openThresh = (base * (1.8 - 0.6 * _gateSensitivity)).clamp(
      5e-4,
      1.0,
    );
    final double closeThresh = (base * (1.3 - 0.5 * _gateSensitivity)).clamp(
      3e-4,
      1.0,
    );
    if (_gateOpen) {
      if (rms < closeThresh) _gateOpen = false;
    } else {
      if (rms > openThresh) _gateOpen = true;
    }
    _gate = _smooth(_gate, _gateOpen ? 1.0 : 0.0, 0.25);
    // Update noise baseline: track when closed, decay slowly when open
    if (!_gateOpen) {
      _noiseRms = _smooth(_noiseRms, rms, 0.12);
    } else {
      _noiseRms = _smooth(_noiseRms, math.min(_noiseRms, rms), 0.01);
    }
    final double level = _normalize(rms * 4.0);
    // Fast attack, slower release for meter
    if (level > _meterLevel) {
      _meterLevel = _meterLevel + (level - _meterLevel) * 0.7;
    } else {
      _meterLevel = _meterLevel + (level - _meterLevel) * 0.2;
    }
    // Keep a smoothed amplitude for visuals
    _amplitude = _smooth(_amplitude, level * _gate, 0.25);

    // Simple band energies via Goertzel at a few centers in each band
    final double lowMag = _avgMagnitude(samples, <double>[60, 120, 200]);
    final double midMag = _avgMagnitude(samples, <double>[400, 800, 1600]);
    final double highMag = _avgMagnitude(samples, <double>[3000, 5000, 7000]);
    if (!_gateOpen) {
      _lowFloor = _smooth(_lowFloor, lowMag, 0.15);
      _midFloor = _smooth(_midFloor, midMag, 0.15);
      _highFloor = _smooth(_highFloor, highMag, 0.15);
    } else {
      _lowFloor = _smooth(_lowFloor, math.min(_lowFloor, lowMag), 0.02);
      _midFloor = _smooth(_midFloor, math.min(_midFloor, midMag), 0.02);
      _highFloor = _smooth(_highFloor, math.min(_highFloor, highMag), 0.02);
    }
    const double floorMargin = 1.3;
    final double lowClean = math.max(0.0, lowMag - _lowFloor * floorMargin);
    final double midClean = math.max(0.0, midMag - _midFloor * floorMargin);
    final double highClean = math.max(0.0, highMag - _highFloor * floorMargin);
    _low = _smooth(_low, _normalize(lowClean * 6.0) * _gate, 0.2);
    _mid = _smooth(_mid, _normalize(midClean * 5.0) * _gate, 0.2);
    _high = _smooth(_high, _normalize(highClean * 4.0) * _gate, 0.2);

    // Zero-crossing rate as noisiness proxy
    int zc = 0;
    for (int i = 1; i < samples.length; i++) {
      final double a = samples[i - 1];
      final double b = samples[i];
      if ((a >= 0 && b < 0) || (a < 0 && b >= 0)) zc++;
    }
    final double zcr = zc / samples.length;
    _zcr = _smooth(_zcr, (zcr * 3.0).clamp(0.0, 1.0), 0.2);

    // Feature spectrum for centroid/flux/chroma/flatness
    const int featBins = 64;
    final double maxHz = 8000.0;
    final List<double> spec = List<double>.filled(featBins, 0.0);
    final List<double> freqs = List<double>.filled(featBins, 0.0);
    double sumMag = 0.0;
    double num = 0.0; // for centroid
    for (int i = 0; i < featBins; i++) {
      final double f0 = (i / featBins) * maxHz;
      final double f1 = ((i + 1) / featBins) * maxHz;
      final double fMid = (f0 + f1) * 0.5;
      freqs[i] = fMid;
      final double m = _normalize(_goertzel(samples, fMid) * 4.0) * _gate;
      spec[i] = m;
      sumMag += m;
      num += fMid * m;
    }
    // Spectral centroid and rolloff
    final double centroidHz = sumMag > 1e-6 ? (num / sumMag) : 0.0;
    _centroid = _smooth(_centroid, (centroidHz / maxHz).clamp(0.0, 1.0), 0.2);
    // Rolloff at 85% energy
    double acc = 0.0;
    final double target = sumMag * 0.85;
    double rollHz = 0.0;
    for (int i = 0; i < featBins; i++) {
      acc += spec[i];
      if (acc >= target) {
        rollHz = freqs[i];
        break;
      }
    }
    _rolloff = _smooth(_rolloff, (rollHz / maxHz).clamp(0.0, 1.0), 0.2);

    // Spectral flatness: geometric mean / arithmetic mean
    double logSum = 0.0;
    for (int i = 0; i < featBins; i++) {
      logSum += math.log(spec[i] + 1e-6);
    }
    final double geo = math.exp(logSum / featBins);
    final double arith = (sumMag / featBins).clamp(1e-6, 1e9);
    final double flat = (geo / arith).clamp(0.0, 1.0);
    _flatness = _smooth(_flatness, flat, 0.2);

    // Spectral flux and onset detection
    double flux = 0.0;
    if (_prevSpecFeat.length == featBins) {
      for (int i = 0; i < featBins; i++) {
        final double d = spec[i] - _prevSpecFeat[i];
        if (d > 0) flux += d;
      }
      flux = (flux / featBins).clamp(0.0, 1.0);
    }
    _prevSpecFeat = List<double>.from(spec);
    _flux = _smooth(_flux, flux, 0.3);
    _fluxHistory.add(flux);
    if (_fluxHistory.length > _fluxHistMax) {
      _fluxHistory.removeAt(0);
    }
    double thr = 0.18; // fallback
    if (_fluxHistory.length >= 8) {
      final double mean =
          _fluxHistory.reduce((a, b) => a + b) / _fluxHistory.length;
      double variance = 0.0;
      for (final double v in _fluxHistory) {
        final double dv = v - mean;
        variance += dv * dv;
      }
      final double std = math.sqrt(variance / _fluxHistory.length);
      thr = (mean + 0.9 * std).clamp(0.08, 0.5);
    }
    final DateTime nowTs = DateTime.now();
    final bool refractory = nowTs.difference(_lastOnsetAt).inMilliseconds < 120;
    if (!refractory && _gateOpen && flux > thr) {
      _lastOnsetAt = nowTs;
      _onsetPulse = 1.0;
      _onsetTimes.add(nowTs);
      // prune to last 10s
      _onsetTimes.removeWhere(
        (DateTime t) => nowTs.difference(t).inMilliseconds > 10000,
      );
      // Align beat anchor to latest onset if tempo known; else keep updating anchor
      _lastBeatAnchor = nowTs;
    }

    // Estimate BPM from recent onsets
    if (_onsetTimes.length >= 4) {
      final List<double> iois = <double>[];
      for (int i = 1; i < _onsetTimes.length; i++) {
        final double d = (_onsetTimes[i]
                    .difference(_onsetTimes[i - 1])
                    .inMilliseconds /
                1000.0)
            .clamp(0.08, 2.0);
        iois.add(d);
      }
      iois.sort();
      final double median = iois[iois.length ~/ 2];
      double bpm = (60.0 / median);
      // fold to 60..180 bpm range
      while (bpm < 60.0) bpm *= 2.0;
      while (bpm > 180.0) bpm *= 0.5;
      _bpm = _smooth(_bpm, bpm, 0.2);
    }
    // Beat pulse near beat boundaries
    if (_bpm > 0.0) {
      final double period = 60.0 / _bpm;
      final double dtBeat =
          nowTs.difference(_lastBeatAnchor).inMilliseconds / 1000.0;
      if (dtBeat >= period) {
        // advance anchor by integer periods to avoid drift
        final int k = (dtBeat / period).floor();
        _lastBeatAnchor = _lastBeatAnchor.add(
          Duration(milliseconds: (period * k * 1000).round()),
        );
        _beatPulse = 1.0;
      } else {
        final double phase = (dtBeat / period);
        final double nearEdge = math.min(phase, 1.0 - phase);
        if (nearEdge < 0.06) {
          _beatPulse = math.max(_beatPulse, 0.9);
        }
      }
    }

    // Chroma: accumulate energy per pitch class
    final List<double> chromaAcc = List<double>.filled(12, 0.0);
    for (int i = 0; i < featBins; i++) {
      final double f = freqs[i];
      if (f < 50.0) continue; // ignore sub-bass / DC
      final double mag = spec[i];
      if (mag <= 0) continue;
      final double midi = 69.0 + 12.0 * (math.log(f / 440.0) / math.ln2);
      final int pc = ((midi.round()) % 12 + 12) % 12;
      chromaAcc[pc] += mag;
    }
    double totalChroma = chromaAcc.reduce((a, b) => a + b).clamp(1e-6, 1e9);
    int peak = 0;
    double peakVal = 0.0;
    for (int i = 0; i < 12; i++) {
      final double v = chromaAcc[i] / totalChroma;
      _chroma[i] = _smooth(_chroma[i], v, 0.25);
      if (_chroma[i] > peakVal) {
        peakVal = _chroma[i];
        peak = i;
      }
    }
    _keyHueStrength = _smooth(_keyHueStrength, peakVal.clamp(0.0, 1.0), 0.2);
    _keyHue = (peak / 12.0) * 360.0;

    if (mounted) setState(() {});
  }

  double _avgMagnitude(List<double> samples, List<double> freqs) {
    double sum = 0.0;
    for (final double f in freqs) {
      sum += _goertzel(samples, f);
    }
    return sum / freqs.length;
  }

  double _goertzel(List<double> samples, double targetHz) {
    final int n = samples.length;
    final double k = (0.5 + ((n * targetHz) / _sampleRate)).floorToDouble();
    final double w = (2 * math.pi / n) * k;
    final double cosine = math.cos(w);
    final double sine = math.sin(w);
    final double coeff = 2.0 * cosine;
    double q0 = 0.0, q1 = 0.0, q2 = 0.0;
    for (int i = 0; i < n; i++) {
      q0 = coeff * q1 - q2 + samples[i];
      q2 = q1;
      q1 = q0;
    }
    final double real = q1 - q2 * cosine;
    final double imag = q2 * sine;
    final double mag = math.sqrt(real * real + imag * imag) / n;
    return mag;
  }

  double _normalize(double v) {
    // Map roughly 0..1+ into 0..1 with soft knee
    final double x = v.clamp(0.0, 2.0);
    return x / (1.0 + x);
  }

  double _smooth(double current, double target, double alpha) {
    return current + (target - current) * alpha;
  }

  List<double> _applyBackgroundFilter(List<double> spec) {
    if (_bgSpec.length != spec.length) {
      // Start from zero so initial frames are visible; learn ambient over time
      _bgSpec = List<double>.filled(spec.length, 0.0);
    }
    final double lr = _gateOpen ? _bgLearnRateOpen : _bgLearnRateClosed;
    final List<double> cleaned = List<double>.filled(spec.length, 0.0);
    for (int i = 0; i < spec.length; i++) {
      // Learn ambient background per bin
      _bgSpec[i] = _bgSpec[i] + (spec[i] - _bgSpec[i]) * lr;
      if (_bgFilterEnabled) {
        final double bg = _bgSpec[i] * (1.0 + _bgMargin);
        cleaned[i] = math.max(0.0, spec[i] - bg);
      } else {
        cleaned[i] = spec[i];
      }
    }
    return cleaned;
  }

  List<double> _computeSpectrumSnapshot({int bins = 48}) {
    if (_sampleBuffer.length < _fftSize) {
      return List<double>.filled(bins, 0.0);
    }
    final List<double> window = _sampleBuffer.sublist(
      _sampleBuffer.length - _fftSize,
    );
    // Remove DC offset
    final List<double> samples = List<double>.from(window);
    double mean = 0.0;
    for (int i = 0; i < samples.length; i++) {
      mean += samples[i];
    }
    mean /= samples.length;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = samples[i] - mean;
    }
    // Very simple magnitude bands using Goertzel spaced up to ~8kHz
    final double maxHz = 8000;
    final List<double> out = List<double>.filled(bins, 0.0);
    for (int i = 0; i < bins; i++) {
      final double f0 = (i / bins) * maxHz;
      final double f1 = ((i + 1) / bins) * maxHz;
      final double fMid = (f0 + f1) * 0.5;
      out[i] = _normalize(_goertzel(samples, fMid) * 4.0);
    }
    // Adaptive background subtraction per bin
    final List<double> outClean = _applyBackgroundFilter(out);
    // Keep a minimal floor so radial bars show subtle motion while learning
    for (int i = 0; i < outClean.length; i++) {
      outClean[i] = math.max(outClean[i], 0.01 * out[i]);
    }
    // Apply gate and smooth to reduce jitter
    if (_specSmooth.length != bins) {
      _specSmooth = List<double>.filled(bins, 0.0);
    }
    for (int i = 0; i < bins; i++) {
      final double v = outClean[i] * _gate;
      _specSmooth[i] = _smooth(_specSmooth[i], v, 0.25);
    }
    return List<double>.from(_specSmooth);
  }

  // Choose base hue from chroma (if confident) else from spectral centroid
  double _currentHueBase() {
    final double chromaWeight = _keyHueStrength.clamp(0.0, 1.0);
    final double centroidHue = (20.0 + 220.0 * _centroid) % 360.0;
    final double hue =
        (_keyHue * chromaWeight + centroidHue * (1.0 - chromaWeight)) % 360.0;
    return hue;
  }

  // Stroke color mapping combining hue base, amplitude and beat
  Color _strokeColor({
    required double hueBase,
    required double amp,
    required double centroid,
    required double beatPulse,
  }) {
    final double hue = (hueBase + amp * 90.0) % 360.0;
    final double sat = (0.7 + 0.25 * (centroid)).clamp(0.0, 1.0);
    final double val = (0.85 + 0.15 * (amp + 0.6 * beatPulse)).clamp(0.0, 1.0);
    return HSVColor.fromAHSV(1.0, hue, sat, val).toColor();
  }

  void _randomize() {
    setState(() {
      _setNewBaseRandom(_numHarmonics);
      // Do NOT reset _a/_b/_c/_d here; they will smoothly morph to new base
      // via _stepMorph alpha smoothing using _reactSpeed.
    });
  }

  void _setNewBaseRandom(int n) {
    final math.Random random = math.Random();
    final List<double> newA = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    final List<double> newB = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    final List<double> newC = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    final List<double> newD = List<double>.generate(
      n,
      (int i) => (random.nextDouble() - 0.5) * 0.6,
    );
    if (_cosOnly) {
      for (int i = 0; i < n; i++) {
        newB[i] = 0.0;
        newD[i] = 0.0;
      }
    }
    _aBase = newA;
    _bBase = newB;
    _cBase = newC;
    _dBase = newD;
  }

  void _setHarmonics(int n) {
    setState(() {
      // Enforce safe range to avoid UI/logic assertions
      final int clamped = n.clamp(3, 64);
      _numHarmonics = clamped;
      // Extend/trim arrays and keep current values; bases get new randoms
      void _resize(List<double> list, int len) {
        if (list.length < len) {
          list.addAll(List<double>.filled(len - list.length, 0.0));
        } else if (list.length > len) {
          list.removeRange(len, list.length);
        }
      }

      _resize(_a, clamped);
      _resize(_b, clamped);
      _resize(_c, clamped);
      _resize(_d, clamped);
      _resize(_aBase, clamped);
      _resize(_bBase, clamped);
      _resize(_cBase, clamped);
      _resize(_dBase, clamped);
      _resize(_phi, clamped);
      _resize(_psi, clamped);
      _setNewBaseRandom(clamped);
      // Ensure symmetry slider/value stays valid when harmonics decrease
      _symmetryOrder = _symmetryOrder.clamp(1, _numHarmonics);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fourier Art'),
        actions: [
          PopupMenuButton<VisualMode>(
            tooltip: 'Visualization',
            icon: const Icon(Icons.layers),
            onSelected: (VisualMode m) => setState(() => _mode = m),
            itemBuilder:
                (BuildContext context) => <PopupMenuEntry<VisualMode>>[
                  const PopupMenuItem(
                    value: VisualMode.classic,
                    child: Text('Classic'),
                  ),
                  const PopupMenuItem(
                    value: VisualMode.lissajous,
                    child: Text('Lissajous'),
                  ),
                  const PopupMenuItem(
                    value: VisualMode.radialBars,
                    child: Text('Radial Bars'),
                  ),
                ],
          ),
          IconButton(
            tooltip:
                _audioReactive
                    ? 'Disable audio reactive'
                    : 'Enable audio reactive',
            icon: Icon(_audioReactive ? Icons.graphic_eq : Icons.volume_off),
            onPressed: () => setState(() => _audioReactive = !_audioReactive),
          ),
          IconButton(
            tooltip: 'Randomize shape',
            icon: const Icon(Icons.casino),
            onPressed: _randomize,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Stack(
                  children: [
                    if (_mode == VisualMode.classic && _classicImage != null)
                      Positioned.fill(
                        child: Center(
                          child: SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: CustomPaint(
                              painter: _ImagePainter(_classicImage!),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      )
                    else
                      CustomPaint(
                        painter:
                            _mode == VisualMode.classic
                                ? _FourierPainter(
                                  a: _a,
                                  b:
                                      _cosOnly
                                          ? List<double>.filled(_b.length, 0.0)
                                          : _b,
                                  c: _c,
                                  d:
                                      _cosOnly
                                          ? List<double>.filled(_d.length, 0.0)
                                          : _d,
                                  phi: _phi,
                                  psi: _psi,
                                  t: _time,
                                  audioReactive: _audioReactive,
                                  low: _low * _lowInfluence,
                                  mid: _mid * _midInfluence,
                                  high: _high * _highInfluence,
                                  amplitude: _amplitude,
                                  strokeWidth: _strokeWidth,
                                  fillShape: _fillShape,
                                  symmetryOrder: _symmetryOrder,
                                  resolution: _resolution,
                                  pixelate: _pixelGrid,
                                  scaleMultiplier:
                                      1.0 +
                                      0.12 * (_amplitude + 0.6 * _beatPulse),
                                  onsetPulse: _onsetPulse,
                                  strokeColor: _strokeColor(
                                    hueBase: _currentHueBase(),
                                    amp: _amplitude,
                                    centroid: _centroid,
                                    beatPulse: _beatPulse,
                                  ),
                                )
                                : _mode == VisualMode.lissajous
                                ? _LissajousPainter(
                                  t: _time,
                                  amplitude: _amplitude,
                                  low: _low,
                                  mid: _mid,
                                  high: _high,
                                  strokeWidth: _strokeWidth,
                                  beatPulse: _beatPulse,
                                  onsetPulse: _onsetPulse,
                                  strokeColor: _strokeColor(
                                    hueBase: _currentHueBase(),
                                    amp: _amplitude,
                                    centroid: _centroid,
                                    beatPulse: _beatPulse,
                                  ),
                                )
                                : _RadialBarsPainter(
                                  spectrum: _computeSpectrumSnapshot(),
                                  amplitude: _amplitude,
                                  baseHue: _currentHueBase(),
                                  onsetPulse: _onsetPulse,
                                ),
                        size: Size.infinite,
                      ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _VolumeMeter(value: _micGranted ? _meterLevel : 0.0),
                          const SizedBox(height: 6),
                          _MicStatusBadge(
                            micGranted: _micGranted,
                            streamActive: _streamActive,
                            hasSignal: _hasRecentSignal,
                            onOpenSettings: () async {},
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('React', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _reactStrength,
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: _reactStrength.toStringAsFixed(2),
                  onChanged: (double v) => setState(() => _reactStrength = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Harmonics', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _numHarmonics.toDouble(),
                  min: 3,
                  max: 16,
                  divisions: 13,
                  label: _numHarmonics.toString(),
                  onChanged: (double v) => _setHarmonics(v.round()),
                ),
              ),
              Switch(
                value: _cosOnly,
                onChanged: (bool v) {
                  setState(() {
                    _cosOnly = v;
                    if (_cosOnly) {
                      for (int i = 0; i < _b.length; i++) {
                        _bBase[i] = 0.0;
                        _dBase[i] = 0.0;
                        _b[i] = 0.0;
                        _d[i] = 0.0;
                      }
                    }
                  });
                },
              ),
              const Text('Cos-only', style: TextStyle(color: Colors.white)),
            ],
          ),
          Row(
            children: [
              const Text('Symmetry', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _symmetryOrder.toDouble(),
                  min: 1,
                  max: _numHarmonics.toDouble(),
                  divisions: (_numHarmonics - 1).clamp(1, 100),
                  label: _symmetryOrder.toString(),
                  onChanged:
                      (double v) => setState(
                        () =>
                            _symmetryOrder = v.round().clamp(1, _numHarmonics),
                      ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Resolution', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _resolution.toDouble(),
                  min: 40,
                  max: 160,
                  divisions: 12,
                  label: '${_resolution}px',
                  onChanged:
                      (double v) => setState(() => _resolution = v.round()),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Pixel Grid', style: TextStyle(color: Colors.white)),
              Switch(
                value: _pixelGrid,
                onChanged: (bool v) => setState(() => _pixelGrid = v),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Auto', style: TextStyle(color: Colors.white)),
              Switch(
                value: _autoRandomize,
                onChanged:
                    (bool v) => setState(() {
                      _autoRandomize = v;
                      _autoTimer = 0.0;
                    }),
              ),
              const SizedBox(width: 8),
              const Text('Interval', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _autoIntervalSec,
                  min: 2,
                  max: 60,
                  divisions: 58,
                  label: '${_autoIntervalSec.toStringAsFixed(0)}s',
                  onChanged: (double v) => setState(() => _autoIntervalSec = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Speed', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _reactSpeed,
                  min: 0.2,
                  max: 3.0,
                  divisions: 28,
                  label: _reactSpeed.toStringAsFixed(2),
                  onChanged: (double v) => setState(() => _reactSpeed = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('BG Filter', style: TextStyle(color: Colors.white)),
              Switch(
                value: _bgFilterEnabled,
                onChanged: (bool v) => setState(() => _bgFilterEnabled = v),
              ),
              const SizedBox(width: 8),
              const Text('Margin', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _bgMargin,
                  min: 0.0,
                  max: 0.6,
                  divisions: 24,
                  label: _bgMargin.toStringAsFixed(2),
                  onChanged: (double v) => setState(() => _bgMargin = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Gate Sens.', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _gateSensitivity,
                  min: 0.4,
                  max: 1.6,
                  divisions: 24,
                  label: _gateSensitivity.toStringAsFixed(2),
                  onChanged: (double v) => setState(() => _gateSensitivity = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Stroke', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _strokeWidth,
                  min: 0,
                  max: 6,
                  divisions: 12,
                  label: _strokeWidth.toStringAsFixed(1),
                  onChanged: (double v) => setState(() => _strokeWidth = v),
                ),
              ),
              Switch(
                value: _fillShape,
                onChanged: (bool v) => setState(() => _fillShape = v),
              ),
              const Text('Fill', style: TextStyle(color: Colors.white)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMeter('Low', _low),
              _buildMeter('Mid', _mid),
              _buildMeter('High', _high),
              _buildMeter('Amp', _amplitude),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Low→shape', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _lowInfluence,
                  min: 0,
                  max: 1.2,
                  divisions: 12,
                  onChanged: (double v) => setState(() => _lowInfluence = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Mid→shape', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _midInfluence,
                  min: 0,
                  max: 1.2,
                  divisions: 12,
                  onChanged: (double v) => setState(() => _midInfluence = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('High→shape', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: _highInfluence,
                  min: 0,
                  max: 1.2,
                  divisions: 12,
                  onChanged: (double v) => setState(() => _highInfluence = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeter(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          width: 50,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.lightBlueAccent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FourierPainter extends CustomPainter {
  _FourierPainter({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.phi,
    required this.psi,
    required this.t,
    required this.audioReactive,
    required this.low,
    required this.mid,
    required this.high,
    required this.amplitude,
    required this.strokeWidth,
    required this.fillShape,
    this.symmetryOrder = 1,
    this.resolution = 80,
    this.pixelate = false,
    this.scaleMultiplier = 1.0,
    this.onsetPulse = 0.0,
    required this.strokeColor,
  });

  final List<double> a;
  final List<double> b;
  final List<double> c;
  final List<double> d;
  final List<double> phi;
  final List<double> psi;
  final double t;
  final bool audioReactive;
  final double low;
  final double mid;
  final double high;
  final double amplitude;
  final double strokeWidth;
  final bool fillShape;
  final int symmetryOrder;
  final int resolution;
  final bool pixelate;
  final double scaleMultiplier;
  final double onsetPulse;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double minDim = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    // Compute one fundamental loop
    final int baseSteps = math.max(
      40,
      resolution * 10 ~/ math.max(1, symmetryOrder),
    );
    final double dt = (2 * math.pi) / (baseSteps - 1);
    final List<Offset> basePoints = <Offset>[];
    double maxAbs = 1e-6;

    for (int i = 0; i < baseSteps; i++) {
      final double tt = dt * i;
      double x = 0.0;
      double y = 0.0;
      for (int k = 0; k < a.length; k++) {
        final double kk = (k + 1).toDouble();
        final double phaseX =
            phi[k] + kk * (t * 0.6 + (audioReactive ? amplitude * 0.4 : 0.0));
        final double phaseY =
            psi[k] + kk * (t * 0.6 + (audioReactive ? amplitude * 0.4 : 0.0));

        x +=
            a[k] * math.cos(kk * tt + phaseX) +
            b[k] * math.sin(kk * tt + phaseX);
        y +=
            c[k] * math.cos(kk * tt + phaseY) +
            d[k] * math.sin(kk * tt + phaseY);
      }
      basePoints.add(Offset(x, y));
      maxAbs = math.max(maxAbs, math.max(x.abs(), y.abs()));
    }

    // Scale to viewport with padding
    final double scale = (minDim * 0.42) / maxAbs * scaleMultiplier;
    for (int i = 0; i < basePoints.length; i++) {
      basePoints[i] = basePoints[i] * scale;
    }

    // Build symmetric path by rotating the base curve symmetryOrder times
    final Path path = Path();
    for (int s = 0; s < math.max(1, symmetryOrder); s++) {
      final double angle = (2 * math.pi * s) / math.max(1, symmetryOrder);
      final double cosA = math.cos(angle);
      final double sinA = math.sin(angle);
      for (int i = 0; i < basePoints.length; i++) {
        final Offset p = basePoints[i];
        final Offset pr = Offset(
          p.dx * cosA - p.dy * sinA,
          p.dx * sinA + p.dy * cosA,
        );
        if (s == 0 && i == 0) {
          path.moveTo(pr.dx, pr.dy);
        } else {
          path.lineTo(pr.dx, pr.dy);
        }
      }
      path.close();
    }
    // do not close here; individual loops closed above
    path.fillType = PathFillType.evenOdd;

    // Stroke/fill or pixel grid depending on resolution mode
    if (resolution <= 1000000) {
      // Regular vector stroke/fill path
      if (fillShape) {
        final Paint fillPaint =
            Paint()
              ..style = PaintingStyle.fill
              ..color = Colors.purpleAccent.withOpacity(
                (0.35 + 0.45 * amplitude + 0.2 * onsetPulse).clamp(0.1, 0.95),
              );
        canvas.drawPath(path, fillPaint);
      }
      if (strokeWidth > 0.0) {
        final Paint stroke =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (strokeWidth + 2.0 * onsetPulse)
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = strokeColor;
        canvas.drawPath(path, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FourierPainter oldDelegate) {
    return true;
  }
}

class _LissajousPainter extends CustomPainter {
  _LissajousPainter({
    required this.t,
    required this.amplitude,
    required this.low,
    required this.mid,
    required this.high,
    required this.strokeWidth,
    required this.beatPulse,
    required this.onsetPulse,
    required this.strokeColor,
  });

  final double t;
  final double amplitude;
  final double low;
  final double mid;
  final double high;
  final double strokeWidth;
  final double beatPulse;
  final double onsetPulse;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double minDim = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    final int steps = 1000;
    final Path path = Path();
    final double a = 3.0 + (low * 2.0);
    final double b = 2.0 + (mid * 3.0);
    final double delta = (high * math.pi) + t * 0.6;
    final double r =
        (minDim * 0.4) * (0.7 + 0.3 * (amplitude + 0.6 * beatPulse));

    for (int i = 0; i <= steps; i++) {
      final double tt = (i / steps) * 2 * math.pi;
      final double x = r * math.sin(a * tt + delta);
      final double y = r * math.sin(b * tt);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (strokeWidth > 0.0) {
      final Paint stroke =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (strokeWidth + 2.0 * onsetPulse)
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = strokeColor;
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LissajousPainter oldDelegate) => true;
}

class _RadialBarsPainter extends CustomPainter {
  _RadialBarsPainter({
    required this.spectrum,
    required this.amplitude,
    required this.baseHue,
    required this.onsetPulse,
  });

  final List<double> spectrum; // 0..1 per bin
  final double amplitude;
  final double baseHue;
  final double onsetPulse;

  @override
  void paint(Canvas canvas, Size size) {
    final double minDim = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.translate(center.dx, center.dy);

    final int n = spectrum.length;
    final double baseRadius = minDim * 0.2;
    final double maxExtra = minDim * 0.35;
    final double angleStep = (2 * math.pi) / n;

    for (int i = 0; i < n; i++) {
      final double v = spectrum[i].clamp(0.0, 1.0);
      final double a = i * angleStep;
      final double len = baseRadius + v * maxExtra * (0.6 + 0.4 * amplitude);
      final Offset p0 = Offset.fromDirection(a, baseRadius);
      final Offset p1 = Offset.fromDirection(a, len);
      final Paint paint =
          Paint()
            ..strokeWidth = (2.5 + 2.5 * onsetPulse)
            ..strokeCap = StrokeCap.round
            ..color =
                HSVColor.fromAHSV(
                  1.0,
                  (baseHue + (i / n) * 180.0) % 360.0,
                  0.85,
                  (0.85 + 0.15 * amplitude).clamp(0.0, 1.0),
                ).toColor();
      canvas.drawLine(p0, p1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadialBarsPainter oldDelegate) => true;
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect dst = Offset.zero & size;
    final Paint p =
        Paint()..filterQuality = FilterQuality.none; // keep crisp pixels
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) =>
      oldDelegate.image != image;
}

class _VolumeMeter extends StatelessWidget {
  const _VolumeMeter({required this.value});

  final double value; // 0..1

  @override
  Widget build(BuildContext context) {
    final double clamped = value.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Container(
            width: 100,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Colors.greenAccent,
                      Colors.yellowAccent,
                      Colors.redAccent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicStatusBadge extends StatelessWidget {
  const _MicStatusBadge({
    required this.micGranted,
    required this.streamActive,
    required this.hasSignal,
    required this.onOpenSettings,
  });

  final bool micGranted;
  final bool streamActive;
  final bool hasSignal;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    if (!micGranted) {
      label = 'Mic permission needed';
      color = Colors.orange;
    } else if (!streamActive) {
      label = 'Mic starting...';
      color = Colors.amber;
    } else if (!hasSignal) {
      label = 'No signal';
      color = Colors.redAccent;
    } else {
      label = 'Mic OK';
      color = Colors.lightGreen;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onOpenSettings, child: const Text('Sound Input')),
      ],
    );
  }
}
