/// AI Color Match (Evoto P1, research 06 §4.4): moves a photo toward the
/// look of a reference photo, written into the ordinary sliders. Like
/// `LocalAutoTone`, every stage is measured on a 256-px proxy rendered by
/// the app's own reference pipeline, so the sliders reproduce what was
/// measured. Bounded, deterministic, skin-safe.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/image_stats.dart' show isSkinLab;
import '../analysis/proxy.dart';
import '../color/cielab.dart';
import '../color/oklab.dart';
import '../color/srgb.dart';
import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import '../render/engine_constants.dart' show kGradeMaxChroma;
import '../render/rgba_buffer.dart';
import 'auto_edit_provider.dart' show ParamChange;
import 'local_auto_tone.dart' show ProxyRenderer, referenceRendererFor;
import 'reasons.dart';

/// OkLab a, b.
typedef Ab = ({double a, double b});

/// The look of a rendered photo: tone distribution, colour of each tonal
/// band, saturation and skin colour (all OkLab).
class LookStats {
  const LookStats({
    required this.lp05,
    required this.lp20,
    required this.lp50,
    required this.lp80,
    required this.lp95,
    required this.sigmaL,
    required this.shadows,
    required this.mids,
    required this.highlights,
    required this.neutral,
    required this.chroma,
    required this.skinShare,
    this.skin,
  });

  /// OkLab L percentiles.
  final double lp05, lp20, lp50, lp80, lp95;

  /// OkLab L standard deviation (global contrast).
  final double sigmaL;

  /// Mean a, b of the darkest third, the middle third and the brightest
  /// third (by L).
  final Ab shadows, mids, highlights;

  /// Mean a, b of the non-skin, not strongly coloured midtones (grey
  /// world): the white-balance cast. The chroma gate is wide so a cast
  /// does not change which pixels count.
  final Ab neutral;

  /// Mean OkLab chroma of non-skin pixels.
  final double chroma;

  /// Share of skin-coloured pixels, and their mean a, b (null: no skin).
  final double skinShare;
  final Ab? skin;

  /// Skin hue in degrees (null: no skin).
  double? get skinHue {
    final s = skin;
    return s == null ? null : _hueDeg(s.a, s.b);
  }

  factory LookStats.of(RgbaBuffer img) {
    final d = img.data;
    final n = img.pixelCount;
    final ls = Float64List(n), as = Float64List(n), bs = Float64List(n);
    final skinMask = Uint8List(n);
    var lSum = 0.0, l2Sum = 0.0, cSum = 0.0, cN = 0;
    var skinN = 0, skinA = 0.0, skinB = 0.0;
    for (var i = 0, p = 0; i < d.length; i += 4, p++) {
      final r = kSrgbByteToLinear[d[i]];
      final g = kSrgbByteToLinear[d[i + 1]];
      final b = kSrgbByteToLinear[d[i + 2]];
      final o = linearSrgbToOklab(r, g, b);
      ls[p] = o.l;
      as[p] = o.a;
      bs[p] = o.b;
      lSum += o.l;
      l2Sum += o.l * o.l;
      if (isSkinLab(linearSrgbToLab(r, g, b))) {
        skinMask[p] = 1;
        skinN++;
        skinA += o.a;
        skinB += o.b;
      } else if (o.l > 0.15 && o.l < 0.95) {
        cSum += math.sqrt(o.a * o.a + o.b * o.b);
        cN++;
      }
    }
    final sorted = Float64List.fromList(ls)..sort();
    double q(double f) => sorted[((n - 1) * f).round()];
    final t1 = q(1 / 3), t2 = q(2 / 3);
    final sh = _AbMean(), mi = _AbMean(), hi = _AbMean(), ne = _AbMean();
    for (var p = 0; p < n; p++) {
      final l = ls[p];
      final band = l < t1 ? sh : (l > t2 ? hi : mi);
      band.add(as[p], bs[p]);
      final c = math.sqrt(as[p] * as[p] + bs[p] * bs[p]);
      if (skinMask[p] == 0 && l > 0.25 && l < 0.92 && c < 0.12) {
        ne.add(as[p], bs[p]);
      }
    }
    final mean = lSum / n;
    return LookStats(
      lp05: q(0.05),
      lp20: q(0.2),
      lp50: q(0.5),
      lp80: q(0.8),
      lp95: q(0.95),
      sigmaL: math.sqrt(math.max(0, l2Sum / n - mean * mean)),
      shadows: sh.value,
      mids: mi.value,
      highlights: hi.value,
      neutral: ne.count >= n * 0.02 ? ne.value : mi.value,
      chroma: cN == 0 ? 0 : cSum / cN,
      skinShare: skinN / n,
      skin: skinN >= math.max(20, n * 0.01)
          ? (a: skinA / skinN, b: skinB / skinN)
          : null,
    );
  }
}

class _AbMean {
  double a = 0, b = 0;
  int count = 0;
  void add(double x, double y) {
    a += x;
    b += y;
    count++;
  }

  Ab get value => count == 0 ? (a: 0, b: 0) : (a: a / count, b: b / count);
}

double _hueDeg(double a, double b) {
  final h = math.atan2(b, a) * 180 / math.pi;
  return h < 0 ? h + 360 : h;
}

/// Output of [ColorMatch.run].
class ColorMatchResult {
  const ColorMatchResult({
    required this.settings,
    required this.changes,
    required this.renders,
  });

  final DevelopSettings settings;
  final List<ParamChange> changes;
  final int renders;
}

/// Largest move per slider away from the photo's current value (and the
/// grading saturation ceiling): a match is never extreme.
abstract final class ColorMatchBounds {
  static const exposure = 1.5;
  static const tone = 40.0; // contrast, highlights, shadows, whites, blacks
  static const temp = 40.0;
  static const tint = 25.0;
  static const color = 40.0; // vibrance, saturation
  static const gradeSat = 30.0;

  /// Skin hue may move at most this much (degrees).
  static const skinHueDeg = 4.0;
}

typedef _B = ColorMatchBounds;

abstract final class ColorMatch {
  /// Sliders a match writes. Everything else (portrait, masks, HSL, crop,
  /// detail…) stays as it is.
  static final Set<ParamId> managedParams = {
    P.exposure,
    P.contrast,
    P.highlights,
    P.shadows,
    P.whites,
    P.blacks,
    P.temp,
    P.tint,
    P.vibrance,
    P.saturation,
    P.grade(GradeZone.shadows, 'hue'),
    P.grade(GradeZone.shadows, 'sat'),
    P.grade(GradeZone.highlights, 'hue'),
    P.grade(GradeZone.highlights, 'sat'),
  };

  /// The look of a photo: [proxy] (its unedited analysis proxy) rendered
  /// with [settings] (its edit) by [renderer] (default: the CPU reference
  /// pipeline), on a 256-px copy.
  static LookStats lookOf(
    RgbaBuffer proxy, {
    DevelopSettings settings = DevelopSettings.defaults,
    ProxyRenderer? renderer,
  }) {
    final src = makeProxy(proxy, longEdge: kSolverLongEdge);
    final render = renderer ?? referenceRendererFor(src, auxSource: proxy);
    return LookStats.of(render(src, settings));
  }

  /// Moves [base] (the target's current settings) toward [reference]:
  /// WB → exposure → whites/blacks → highlights/shadows → contrast →
  /// exposure → vibrance/saturation → split toning → skin check. [locked]
  /// sliders are never touched.
  static ColorMatchResult run({
    required RgbaBuffer target,
    required LookStats reference,
    DevelopSettings base = DevelopSettings.defaults,
    Set<ParamId> locked = const {},
    ProxyRenderer? renderer,
  }) {
    final src = makeProxy(target, longEdge: kSolverLongEdge);
    final solver = _Solver(
      src,
      renderer ?? referenceRendererFor(src, auxSource: target),
      reference,
      base,
      locked,
    );
    final out = solver.solve();
    return ColorMatchResult(
      settings: out,
      changes: Reasons.diff(
        base,
        out,
        (p, from, to) => 'Matched the reference look',
      ),
      renders: solver.renders,
    );
  }
}

class _Solver {
  _Solver(this.src, this.render, this.ref, this.start, this.locked)
    : _s = start;

  final RgbaBuffer src;
  final ProxyRenderer render;
  final LookStats ref;
  final DevelopSettings start;
  final Set<ParamId> locked;
  DevelopSettings _s;
  int renders = 0;

  LookStats _look([DevelopSettings? s]) {
    renders++;
    return LookStats.of(render(src, s ?? _s));
  }

  /// Sets [p] within ±[bound] of its starting value (and its spec range).
  void _set(ParamId p, double v, double bound) {
    if (locked.contains(p)) return;
    final s0 = start.value(p);
    final spec = ParamRegistry.byId(p);
    _s = _s.withValue(p, spec.clamp(v.clamp(s0 - bound, s0 + bound)));
  }

  DevelopSettings solve() {
    final startLook = _look();
    _whiteBalance();
    _exposure();
    var cur = _look();
    for (var i = 0; i < 2; i++) {
      _set(P.whites, _s.value(P.whites) + 300 * (ref.lp95 - cur.lp95), _B.tone);
      _set(P.blacks, _s.value(P.blacks) + 300 * (ref.lp05 - cur.lp05), _B.tone);
      cur = _look();
    }
    _set(
      P.highlights,
      _s.value(P.highlights) + 250 * (ref.lp80 - cur.lp80),
      _B.tone,
    );
    _set(P.shadows, _s.value(P.shadows) + 250 * (ref.lp20 - cur.lp20), _B.tone);
    cur = _look();
    for (var i = 0; i < 2; i++) {
      final rel = (ref.sigmaL - cur.sigmaL) / math.max(cur.sigmaL, 0.04);
      _set(P.contrast, _s.value(P.contrast) + 120 * rel, _B.tone);
      cur = _look();
    }
    _exposure();
    _saturation();
    _splitToning();
    // Toning and saturation move the overall cast a little: re-balance.
    _secantStep(P.temp, 10, (l) => l.neutral.b, ref.neutral.b, _B.temp);
    _secantStep(P.tint, 10, (l) => l.neutral.a, ref.neutral.a, _B.tint);
    _protectSkin(startLook);
    return _s;
  }

  /// Temp moves OkLab b (blue ↔ yellow), tint moves a (green ↔ magenta):
  /// secant steps on each, matching the neutral cast.
  void _whiteBalance() {
    for (var i = 0; i < 2; i++) {
      _secantStep(P.temp, 20, (l) => l.neutral.b, ref.neutral.b, _B.temp);
      _secantStep(P.tint, 20, (l) => l.neutral.a, ref.neutral.a, _B.tint);
    }
  }

  /// Median L via exposure (log-domain secant).
  void _exposure() {
    if (locked.contains(P.exposure)) return;
    for (var i = 0; i < 3; i++) {
      final cur = _look().lp50;
      if ((cur - ref.lp50).abs() < 0.004) return;
      _secantStep(P.exposure, 0.25, (l) => l.lp50, ref.lp50, _B.exposure);
    }
  }

  /// One secant step on [p] toward `measure(look) == goal`, probing at
  /// ±[probe] for the slope.
  void _secantStep(
    ParamId p,
    double probe,
    double Function(LookStats) measure,
    double goal,
    double bound,
  ) {
    if (locked.contains(p)) return;
    final x0 = _s.value(p);
    final f0 = measure(_look()) - goal;
    final x1 = x0 + (f0 > 0 ? -probe : probe);
    final f1 = measure(_look(_s.withValue(p, x1))) - goal;
    final slope = (f1 - f0) / (x1 - x0);
    if (!slope.isFinite || slope.abs() < 1e-7) return;
    _set(p, x0 - f0 / slope, bound);
  }

  /// Chroma ratio: more colour via vibrance (protects skin), less via
  /// saturation.
  void _saturation() {
    for (var i = 0; i < 2; i++) {
      final cur = _look();
      if (cur.chroma <= 1e-4 || ref.chroma <= 1e-4) return;
      final ratio = ref.chroma / cur.chroma;
      if ((ratio - 1).abs() < 0.03) return;
      if (ratio > 1) {
        final step = math.min(60 * (ratio - 1), 20.0);
        _set(P.vibrance, _s.value(P.vibrance) + step, _B.color);
      } else {
        _set(
          P.saturation,
          _s.value(P.saturation) + 100 * (ratio - 1),
          _B.color,
        );
      }
    }
  }

  /// The reference's shadow and highlight tint relative to its midtones,
  /// on the grading wheels (OkLab hue; saturation 100 = chroma 0.08).
  void _splitToning() {
    final cur = _look();
    for (final (zone, refBand, curBand) in [
      (GradeZone.shadows, ref.shadows, cur.shadows),
      (GradeZone.highlights, ref.highlights, cur.highlights),
    ]) {
      // Only when the reference really tints this band (relative to its
      // midtones): a match adds a tint, it never "neutralizes" one.
      final ra = refBand.a - ref.mids.a, rb = refBand.b - ref.mids.b;
      if (math.sqrt(ra * ra + rb * rb) < 0.01) continue;
      // The band's colour error beyond the global (midtone) error.
      final da = (refBand.a - curBand.a) - (ref.mids.a - cur.mids.a);
      final db = (refBand.b - curBand.b) - (ref.mids.b - cur.mids.b);
      final c = math.sqrt(da * da + db * db);
      if (c < 0.004 || da * ra + db * rb <= 0) continue;
      final hue = P.grade(zone, 'hue'), sat = P.grade(zone, 'sat');
      if (locked.contains(hue) || locked.contains(sat)) continue;
      // A band's wheel reaches only part of its pixels: aim a bit higher.
      _s = _s.withValue(hue, _hueDeg(da, db).roundToDouble() % 360);
      _set(sat, 1.6 * c / kGradeMaxChroma * 100, _B.gradeSat);
    }
  }

  /// Skin hue must stay within a few degrees of where it started: scale
  /// the colour moves (WB, split toning) back until it does.
  void _protectSkin(LookStats startLook) {
    final h0 = startLook.skinHue;
    if (h0 == null) return;
    double drift(DevelopSettings s) {
      final h = _look(s).skinHue;
      if (h == null) return 0;
      final d = (h - h0).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    if (drift(_s) <= _B.skinHueDeg) return;
    final full = _s;
    DevelopSettings scaled(double k) {
      var s = full;
      for (final p in [
        P.temp,
        P.tint,
        P.grade(GradeZone.shadows, 'sat'),
        P.grade(GradeZone.highlights, 'sat'),
      ]) {
        final a = start.value(p), b = full.value(p);
        s = s.withValue(p, a + (b - a) * k);
      }
      return s;
    }

    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 6; i++) {
      final mid = (lo + hi) / 2;
      if (drift(scaled(mid)) <= _B.skinHueDeg) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    _s = scaled(lo);
  }
}
