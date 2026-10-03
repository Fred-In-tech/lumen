import 'dart:math' as math;

import '../analysis/image_stats.dart';
import '../color/srgb.dart';
import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import '../render/rgba_buffer.dart';
import 'ai_style.dart';
import 'auto_tone_constants.dart';
import 'tone_measure.dart';

typedef _C = AutoToneConstants;

/// Median-luminance exposure target with a hysteresis band: images whose
/// median already lies in [low, high] keep their exposure.
class ExposureTarget {
  const ExposureTarget({
    required this.key,
    required this.low,
    required this.high,
    required this.safeLow,
    required this.safeHigh,
  });

  final double key;
  final double low;
  final double high;

  /// Wider band the other sliders may move an uncorrected median within.
  final double safeLow;
  final double safeHigh;

  bool accepts(double medianY) => medianY >= low && medianY <= high;
}

/// What [AutoToneSolver.solve] produced.
class SolveOutput {
  const SolveOutput(
    this.settings,
    this.key,
    this.wbStrength,
    this.confidence,
    this.renders,
  );

  final DevelopSettings settings;
  final double key;
  final double wbStrength;
  final double confidence;
  final int renders;
}

/// The staged solver behind `LocalAutoTone` (internal; not exported).
class AutoToneSolver {
  AutoToneSolver({
    required this.src,
    required this.render,
    required this.st0,
    required this.targets,
    required this.locked,
    required DevelopSettings start,
  }) : _s = start;

  final RgbaBuffer src;
  final RgbaBuffer Function(RgbaBuffer, DevelopSettings) render;
  final ImageStats st0;
  final AutoToneTargets targets;
  final Set<ParamId> locked;
  DevelopSettings _s;
  int _renders = 0;

  SolveOutput solve({
    required ExposureTarget key,
    required bool lowKey,
    required bool sunset,
    required bool night,
  }) {
    final gate = _smoothstep(
      _C.wbConfidenceLo,
      _C.wbConfidenceHi,
      st0.wb.confidence,
    );
    final strength = _whiteBalance(gate, intentionalHint: sunset || lowKey);
    final correcting = _initialExposure(key, night);
    _whitesBlacks(_measure());
    _highlightsShadows(_measure(), lowKey);
    final sigma = _contrast(_measure());
    _vibrance(ChromaMeasure.of(_render()));
    _dehaze(sigma);
    if (strength >= 1 && gate >= 1) _refineWhiteBalance();
    for (var i = 0; i < _C.refinePasses; i++) {
      _whitesBlacks(_measure());
      _solveExposure(key, night, correcting: correcting);
    }
    return SolveOutput(_s, key.key, strength, 0.5 + 0.4 * gate, _renders);
  }

  void _set(ParamId p, double v) {
    if (!locked.contains(p)) _s = _s.withValue(p, v);
  }

  RgbaBuffer _render([DevelopSettings? settings]) {
    _renders++;
    return render(src, settings ?? _s);
  }

  ToneMeasure _measure([DevelopSettings? settings]) =>
      ToneMeasure.of(_render(settings));

  double _whiteBalance(double gate, {required bool intentionalHint}) {
    final wb = st0.wb;
    final intentional = wb.a > _C.intentionalCastA && intentionalHint;
    final strength =
        targets.wbStrength ??
        (intentional ? _C.wbStrengthIntentional : _C.wbStrength);
    final a = _soft(wb.a, _C.castDeadZoneA);
    final m = _soft(wb.m, _C.castDeadZoneM);
    _set(P.temp, _tempFor(-100 * a / _C.kappaT * strength * gate));
    _set(P.tint, _tintFor(100 * m / _C.kappaG * strength * gate));
    return strength;
  }

  /// Re-measures the cast on the full render and removes what is left.
  void _refineWhiteBalance() {
    for (var i = 0; i < 2; i++) {
      final wb = estimateWhiteBalanceOf(_render());
      final a = _soft(wb.a, _C.castDeadZoneA);
      final m = _soft(wb.m, _C.castDeadZoneM);
      if (a == 0 && m == 0) return;
      _set(P.temp, _tempFor(_s.value(P.temp) - 100 * a / _C.kappaT));
      _set(P.tint, _tintFor(_s.value(P.tint) + 100 * m / _C.kappaG));
    }
  }

  double _tempFor(double v) => v.clamp(-_C.tempClamp, _C.tempClamp).toDouble();
  double _tintFor(double v) => v.clamp(-_C.tintClamp, _C.tintClamp).toDouble();

  /// Returns true when the source median is outside the band (a correction
  /// is underway and the refinement must finish it at the key).
  bool _initialExposure(ExposureTarget key, bool night) {
    final medianY = math.max(srgbToLinear(st0.lumaP.p50), 1e-4);
    if (key.accepts(medianY)) return false;
    var ev = _log2(key.key / medianY).clamp(_C.evMin, _C.evMax).toDouble();
    if (night) ev = math.min(ev, _C.nightEvCap);
    ev = _highlightGuard(ev);
    _set(P.exposure, ev);
    if (ev > _C.preHighlightsFrom) {
      _set(P.highlights, _C.preHighlightsPerEv * ev);
    }
    return true;
  }

  /// Research §6.4 step 4: limit newly clipped pixels.
  double _highlightGuard(double ev) {
    if (ev <= 0) return ev;
    final limit = math.max(_C.clipGuard, 2 * _clippedAt(0));
    if (_clippedAt(ev) <= limit) return ev;
    var lo = ev / 2, hi = ev;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      if (_clippedAt(mid) <= limit) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  double _clippedAt(double ev) {
    final gain = math.pow(2, ev).toDouble();
    final t = _s.value(P.temp), tint = _s.value(P.tint);
    final gr = math.pow(2, _C.kappaT * t / 200).toDouble() * gain;
    final gb = math.pow(2, -_C.kappaT * t / 200).toDouble() * gain;
    final gg = math.pow(2, -_C.kappaG * tint / 100).toDouble() * gain;
    final d = src.data;
    var n = 0;
    for (var i = 0; i < d.length; i += 4) {
      if (kSrgbByteToLinear[d[i]] * gr >= 1 ||
          kSrgbByteToLinear[d[i + 1]] * gg >= 1 ||
          kSrgbByteToLinear[d[i + 2]] * gb >= 1) {
        n++;
      }
    }
    return n / src.pixelCount;
  }

  /// Incremental whites/blacks toward the clip targets (§6.5).
  void _whitesBlacks(ToneMeasure m) {
    const tHi = _C.whiteTarget;
    final pHi = m.highlightP99_5;
    final dw = pHi < tHi ? 400 * (1 - pHi / tHi) : 400 * (tHi / pHi - 1);
    _set(
      P.whites,
      (_s.value(P.whites) + dw).clamp(_C.whitesMin, _C.whitesMax).toDouble(),
    );
    final tLo = _C.blackTarget + targets.blackTargetShift;
    var db = 0.0;
    if (m.p0_5 > tLo) {
      db = -400 * (m.p0_5 - tLo) / (1 - tLo);
    } else if (m.crushFraction > 0.02) {
      db = math.min(20, 400 * (m.crushFraction - 0.02));
    }
    _set(
      P.blacks,
      (_s.value(P.blacks) + db).clamp(_C.blacksMin, _C.blacksMax).toDouble(),
    );
  }

  void _highlightsShadows(ToneMeasure m, bool lowKey) {
    final hl = (300 * math.max(0, m.hiMean - 0.82) + 1500 * m.hiClip).clamp(
      0,
      _C.highlightsMax,
    );
    var highlights = (_s.value(P.highlights) - hl).clamp(
      -_C.highlightsMax,
      0.0,
    );
    if (st0.clipFraction > _C.sourceClipRecover) {
      // Blown source highlights: always pull a little to recover detail.
      highlights = math.min(
        highlights,
        -(_C.recoverBase + _C.recoverPerClip * st0.clipFraction),
      );
    }
    _set(P.highlights, highlights.toDouble());
    var sh =
        (250 * math.max(0, 0.14 - m.loMean) +
                500 * math.max(0, m.loCrush - 0.02))
            .clamp(0, _C.shadowsMax)
            .toDouble();
    if (lowKey) sh *= 0.5;
    _set(P.shadows, sh);
  }

  double _contrast(ToneMeasure m) {
    final target = _C.sigmaTarget + targets.sigmaShift;
    final c = 150 * (target - m.sigmaLStar) / target;
    _set(P.contrast, c.clamp(_C.contrastMin, _C.contrastMax).toDouble());
    return m.sigmaLStar;
  }

  void _vibrance(ChromaMeasure c) {
    final target = _C.chromaTarget + targets.chromaShift;
    var vib = (120 * (target - c.meanChroma) / target)
        .clamp(_C.vibranceMin, _C.vibranceMax)
        .toDouble();
    if (c.highChromaShare > 0.15) vib = math.min(vib, 5);
    var sat = (0.25 * vib).clamp(_C.saturationMin, _C.saturationMax).toDouble();
    if (c.skinShare > 0.12) {
      vib = math.min(vib, 20);
      sat = math.min(sat, 3);
    }
    final cap = targets.vibranceCap;
    if (cap != null) vib = math.min(vib, cap);
    if (targets.skinProtect) sat = math.min(sat, 0);
    _set(P.vibrance, vib);
    _set(P.saturation, sat);
  }

  void _dehaze(double sigma) {
    final target = _C.sigmaTarget + targets.sigmaShift;
    if (sigma >= target ||
        st0.lumaP.p0_5 < _C.dehazeMinBlackPoint ||
        st0.clipFraction > _C.sourceClipRecover) {
      return;
    }
    final d = (250 * (st0.haze - _C.hazeThreshold)).clamp(0, _C.dehazeMax);
    _set(P.dehaze, d.toDouble());
  }

  /// Secant-solves exposure so the rendered median hits the key while
  /// [correcting]; otherwise only pulls a median that left the safety band
  /// back to its nearest edge.
  void _solveExposure(
    ExposureTarget key,
    bool night, {
    required bool correcting,
  }) {
    if (locked.contains(P.exposure)) return;
    var x0 = _s.value(P.exposure);
    final median = _measure().medianY;
    var goal = key.key;
    if (!correcting) {
      if (median >= key.safeLow && median <= key.safeHigh) return;
      goal = median < key.safeLow ? key.safeLow : key.safeHigh;
    }
    double err(double ev) {
      final m = _measure(_s.withValue(P.exposure, ev));
      return _log2(math.max(m.medianY, 1e-5)) - _log2(goal);
    }

    var f0 = _log2(math.max(median, 1e-5)) - _log2(goal);
    var x1 = (x0 - f0).clamp(_C.evMin, _C.evMax).toDouble();
    for (var i = 0; i < 5 && (x1 - x0).abs() > 0.01; i++) {
      final f1 = err(x1);
      if (f1.abs() < 0.02) break;
      var slope = (f1 - f0) / (x1 - x0);
      if (!slope.isFinite || slope < 0.2) slope = 1;
      final next = (x1 - f1 / slope).clamp(_C.evMin, _C.evMax).toDouble();
      x0 = x1;
      f0 = f1;
      x1 = next;
    }
    _set(P.exposure, night ? math.min(x1, _C.nightEvCap) : x1);
  }
}

double _soft(double v, double dead) => v.abs() <= dead ? 0 : v - dead * v.sign;

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _log2(double x) => math.log(x) / math.ln2;
