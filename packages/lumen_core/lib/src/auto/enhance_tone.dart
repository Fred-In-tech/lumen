import 'dart:math' as math;

import '../color/srgb.dart';
import 'enhance_constants.dart';
import 'enhance_scene.dart';
import 'frame_measure.dart';

typedef _C = EnhanceConstants;

/// Stages E–H of research 09 §2 as pure functions of a measured render.
abstract final class EnhanceTone {
  /// Highlights (≤ 0) from clip statistics, skin hot-spots and bright
  /// fabric. Returns the value and which need drove it.
  static (double, HighlightNeed) highlights(
    FrameMeasure m, {
    required double skinHot,
    required double sourceClip,
    required EnhanceScene scene,
  }) {
    final kind = scene.kind;
    // Only what the render clipped itself is recoverable with the slider.
    final recoverable = math.max(0.0, m.hiClip - sourceClip);
    // Large areas just under the clip point hold detail worth showing
    // (calibrated: research pulls on the mean of the brightest tenth, which
    // also "recovers" any normally exposed bright frame).
    final crowded = scene.highKey
        ? 0.0
        : math.max(0, m.nearClip - _C.nearClipFree);
    final general = _C.nearClipGain * crowded + 1500 * recoverable;
    final skin = 220 * math.max(0, skinHot - _C.skinHotStart);
    final fabric = 250 * math.max(0, m.maxP99_5 - _C.whiteHotStart);
    final need = math.max(general, math.max(skin, fabric));
    final cap = kind == SceneKind.portrait
        ? _C.highlightsCapPortrait
        : _C.highlightsCap;
    final cause = need == skin && skin > 0
        ? HighlightNeed.skin
        : need == fabric && fabric > general
        ? HighlightNeed.whites
        : HighlightNeed.general;
    return (-need.clamp(0.0, cap).toDouble(), cause);
  }

  /// Shadows (≥ 0). [underStops] is what darker faces still lack after
  /// exposure (group rule); [iso] caps the lift by noise.
  static double shadows(
    FrameMeasure m, {
    required double underStops,
    required EnhanceScene scene,
    int? iso,
  }) {
    var need =
        250 * math.max(0, 0.14 - m.loMean) +
        500 * math.max(0, m.loCrush - 0.02) +
        60 * underStops;
    var cap = scene.isPeople ? _C.shadowsCapPortrait : _C.shadowsCap;
    if (iso != null && iso > 400) {
      cap *= (1.6 - 0.2 * math.log(iso / 400) / math.ln2).clamp(0.4, 1.0);
    }
    if (scene.lowKey) need *= _C.lowKeyShadows;
    return need.clamp(0.0, cap).toDouble();
  }

  /// Whites from the P99.9 white point (§2.7).
  ///
  /// [extraClip] is what the render clips beyond the source: only that is
  /// pulled back (source-clipped light stays white, never grey).
  /// [sourceHasWhite]: the unedited frame reaches the white target.
  static double whites(
    FrameMeasure m, {
    required double highlights,
    required double skinHot,
    required double extraClip,
    required bool sourceHasWhite,
    required SceneKind kind,
  }) {
    final p = math.max(m.maxP99_9, 1e-3);
    if (p >= _C.whiteTarget) {
      if (extraClip <= 0.001) return 0;
      return (400 * (_C.whiteTarget / p - 1)).clamp(_C.whitesMin, 0).toDouble();
    }
    if (highlights <= _C.whitesSkipHighlights) return 0;
    // A true white (a lamp, a blown window) gets its white back after a
    // highlight pull: never grey. Anything else is only stretched when the
    // frame has no white at all, and then not into the fabric ceiling.
    if (!sourceHasWhite && p >= _C.whiteEnough) return 0;
    final target = sourceHasWhite ? _C.whiteTarget : _C.whiteStretchTo;
    var w = 400 * (1 - p / target);
    if (skinHot > 0) {
      w = math.min(w, 400 * (1 - skinHot / _C.skinHotMax));
    }
    final cap = kind == SceneKind.other || sourceHasWhite
        ? _C.whitesMax
        : _C.whitesMaxPortrait;
    return w.clamp(0.0, cap).toDouble();
  }

  /// Blacks from the P0.1 black point (§2.7).
  static double blacks(
    FrameMeasure m, {
    required EnhanceScene scene,
    double targetShift = 0,
  }) {
    final airy = scene.highKey;
    final target = (airy ? _C.blackTargetAiry : _C.blackTarget) + targetShift;
    final lo = airy
        ? _C.blacksMinAiry
        : scene.isPeople
        ? _C.blacksMinPortrait
        : _C.blacksMin;
    final hi = scene.isPeople ? _C.blacksMaxPortrait : _C.blacksMax;
    if (m.p0_1 > target) {
      return (-400 * (m.p0_1 - target) / (1 - target)).clamp(lo, 0).toDouble();
    }
    if (scene.lowKey || scene.night) return 0;
    if (m.loCrush > 0.02) {
      return (400 * (m.loCrush - 0.02)).clamp(0.0, hi).toDouble();
    }
    return 0;
  }

  /// σ(L*) target of the scene (§2.8).
  static double sigmaTarget(EnhanceScene scene) {
    if (scene.highKey || scene.lowKey) return _C.sigmaKeyed;
    return switch (scene.kind) {
      SceneKind.portrait => _C.sigmaPortrait,
      SceneKind.group => _C.sigmaGroup,
      SceneKind.other => _C.sigmaLandscape,
    };
  }

  /// Contrast pivoting on middle grey. Never negative unless the light is
  /// genuinely [harsh].
  static double contrast(
    FrameMeasure m, {
    required EnhanceScene scene,
    required bool harsh,
    double sigmaShift = 0,
  }) {
    final target = sigmaTarget(scene) + sigmaShift;
    var c = 150 * (target - m.sigmaLStar) / target;
    if (c < 0 && !harsh) return 0;
    var cap = switch (scene.kind) {
      SceneKind.portrait => _C.contrastMaxPortrait,
      SceneKind.group => _C.contrastMaxGroup,
      SceneKind.other => _C.contrastMax,
    };
    if (dynamicRange(m) > 10) cap = math.min(cap, 5);
    c = c.clamp(_C.contrastMin, cap);
    return c.toDouble();
  }

  /// True when a scene without faces is harsh: wide spread, both ends gone.
  static bool harshFrame(FrameMeasure m, EnhanceScene scene) =>
      m.sigmaLStar > _C.harshSigmaFactor * sigmaTarget(scene) &&
      m.clipFraction > _C.harshEndFraction &&
      m.loCrush > _C.harshEndFraction;

  /// Scene dynamic range in stops between the 0.5 % and 99.5 % luma.
  static double dynamicRange(FrameMeasure m) {
    final hi = math.max(srgbToLinear(m.p99_5), 1e-4);
    final lo = math.max(srgbToLinear(m.p0_5), 1e-4);
    return math.log(hi / lo) / math.ln2;
  }

  /// Vibrance and saturation (§2.9) from the non-skin colourfulness.
  static (double, double) colour(
    ChromaReading c, {
    required EnhanceScene scene,
    required bool skinSaturated,
    double chromaShift = 0,
    double? vibranceCap,
    bool skinProtect = false,
  }) {
    final target = _C.chromaTarget + chromaShift;
    final people = scene.isPeople || c.skinShare > _C.skinShareGuard;
    var cap = switch (scene.kind) {
      SceneKind.portrait => _C.vibranceMaxPortrait,
      SceneKind.group => _C.vibranceMaxGroup,
      SceneKind.other => people ? _C.vibranceMaxGroup : _C.vibranceMax,
    };
    if (vibranceCap != null) cap = math.min(cap, vibranceCap);
    var vib = 0.0;
    if (c.meanChroma < target) {
      vib = 120 * (target - c.meanChroma) / target;
    } else if (c.meanChroma > 1.4 * target) {
      vib = -60 * (c.meanChroma - 1.4 * target) / target;
    }
    if (c.highChromaShare > 0.15) vib = math.min(vib, 5);
    // A grey scene with a few strong colours is not a muted scene.
    if (c.vividShare > _C.vividShareGuard) {
      vib = math.min(vib, _C.vividVibranceMax);
    }
    if (skinSaturated) vib = math.min(vib, 0);
    vib = vib.clamp(_C.vibranceMin, cap);
    var sat = (0.2 * vib).clamp(_C.saturationMin, cap / 4);
    if (skinProtect || skinSaturated) sat = math.min(sat, 0);
    return (vib.toDouble(), sat.toDouble());
  }
}

/// What drove a highlights pull (picks the reason shown to the user).
enum HighlightNeed { general, skin, whites }
