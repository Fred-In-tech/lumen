import 'dart:math' as math;

import '../color/srgb.dart';
import 'enhance_constants.dart';
import 'enhance_pixels.dart';
import 'enhance_scene.dart';
import 'frame_measure.dart';
import 'skin_bands.dart';

typedef _C = EnhanceConstants;

double _log2(double x) => math.log(x) / math.ln2;

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// What the exposure stage decided, and why.
class ExposurePlan {
  const ExposurePlan({
    required this.ev,
    required this.faceEv,
    required this.globalEv,
    required this.faceWeight,
    required this.underStops,
    required this.facesInBand,
  });

  /// Exposure change in stops (damped, clamped).
  final double ev;

  /// What the faces alone ask for (0 inside their bands).
  final double faceEv;

  /// What the histogram alone asks for.
  final double globalEv;

  /// Share of the decision the faces carried (0 without faces).
  final double faceWeight;

  /// Stops the darker faces still lack: handed to Shadows (group rule).
  final double underStops;

  /// Every weighted face already sat inside its accept band.
  final bool facesInBand;

  bool get faceDriven => faceWeight >= 0.5;
}

/// Stage D (research 09 §2.4): face-anchored exposure with a dead band,
/// blended with a damped histogram opinion.
abstract final class EnhanceExposure {
  /// [frame] and [faces] are measured after white balance. [keyScale]
  /// scales the histogram key (a style's look).
  static ExposurePlan plan({
    required FrameMeasure frame,
    required List<FaceRead> faces,
    required EnhanceScene scene,
    double keyScale = 1,
  }) {
    final global = _globalEv(frame, scene, keyScale);
    final lo = scene.isPeople ? _C.evMinPortrait : _C.evMinOther;
    var hi = scene.isPeople ? _C.evMaxPortrait : _C.evMaxOther;
    if (scene.night) hi = math.min(hi, _C.evNightMax);
    if (faces.isEmpty) {
      return ExposurePlan(
        ev: (_C.dampGlobal * global).clamp(lo, hi).toDouble(),
        faceEv: 0,
        globalEv: global,
        faceWeight: 0,
        underStops: 0,
        facesInBand: true,
      );
    }
    final inBand = faces.every(
      (f) => f.region.weight <= _C.groupFaceWeight || f.target.accepts(f.lStar),
    );
    final faceEv = inBand ? 0.0 : _faceEv(faces);
    var conf = 0.0;
    for (final f in faces) {
      conf += f.region.weight * f.target.confidence;
    }
    var wF = math.min(
      0.9,
      _smoothstep(_C.faceAreaLow, _C.faceAreaHigh, scene.faceArea) *
          (0.6 + 0.4 * conf),
    );
    // A blown frame hides how bright the faces really are (their white
    // reference is gone): let the histogram speak when it asks for less.
    final blown = global < 0 && frame.clipFraction > _C.blownClip;
    if (blown) wF *= 0.5;
    var ev = wF * _C.dampFaces * faceEv + (1 - wF) * _C.dampGlobal * global;
    // The histogram may not push a face out of (or further from) its band.
    ev = _keepFaces(ev, faces);
    if (inBand) {
      ev = ev.clamp(blown ? -1.0 : -_C.inBandEvMax, _C.unknownToneEvMax);
    }
    ev = ev.clamp(lo, hi);
    var under = 0.0;
    for (final f in faces) {
      final e = f.target.error(f.lStarAt(ev));
      if (e > 0) under += f.region.weight * e / 12;
    }
    return ExposurePlan(
      ev: ev.toDouble(),
      faceEv: faceEv,
      globalEv: global,
      faceWeight: wF,
      underStops: under,
      facesInBand: inBand,
    );
  }

  /// The EV minimising the weighted out-of-band error with a gentle pull
  /// to each face's centre (§2.4), searched on a fixed grid.
  static double _faceEv(List<FaceRead> faces) {
    var best = 0.0, bestCost = double.infinity;
    for (var k = -100; k <= 125; k++) {
      final ev = k / 50;
      var cost = 0.0;
      for (final f in faces) {
        final l = f.lStarAt(ev);
        final e = f.target.error(l);
        final c = l - _aim(f);
        cost += f.region.weight * (e * e + 0.15 * c * c);
      }
      // Ties go to the smaller move (deterministic, conservative).
      if (cost < bestCost - 1e-9 ||
          ((cost - bestCost).abs() <= 1e-9 && ev.abs() < best.abs())) {
        bestCost = cost;
        best = ev;
      }
    }
    return _capBrightest(best, faces);
  }

  /// Where a face is pulled to: a little inside the band edge it missed
  /// (the smallest sufficient move), or nowhere when it is already inside.
  /// Calibrated: research pulls every face to its band centre, which moves
  /// faces that only just missed their band by most of a stop.
  static double _aim(FaceRead f) {
    final l = f.lStar, t = f.target;
    if (l < t.low) return t.low + _C.bandAim * (t.centre - t.low);
    if (l > t.high) return t.high - _C.bandAim * (t.high - t.centre);
    return l;
  }

  /// Group rule: no weighted face may end above its band.
  static double _capBrightest(double ev, List<FaceRead> faces) {
    var out = ev;
    for (final f in faces) {
      if (f.region.weight <= _C.groupFaceWeight) continue;
      final top = _evFor(f, f.target.high);
      // A face already above its band is brought down to it, not past it.
      if (out > top) out = math.max(top, math.min(out, 0));
    }
    return out;
  }

  /// Limits [ev] so no weighted face crosses a band edge it was inside of,
  /// and no face outside moves further out.
  static double _keepFaces(double ev, List<FaceRead> faces) {
    var lo = double.negativeInfinity, hi = double.infinity;
    for (final f in faces) {
      if (f.region.weight <= _C.groupFaceWeight) continue;
      final l = f.lStar;
      var top = l > f.target.high ? 0.0 : _evFor(f, f.target.high);
      if (f.target.confidence == 0) {
        // Unknown tone: never towards a light-skin target.
        top = math.min(
          top,
          math.min(_C.unknownToneEvMax, math.max(0, _evFor(f, _C.highDark))),
        );
      } else if (l >= f.target.low) {
        top = math.min(top, _C.inBandEvMax);
      }
      hi = math.min(hi, top);
      lo = math.max(lo, l < f.target.low ? 0 : _evFor(f, f.target.low));
    }
    if (lo > hi) return ev.clamp(math.min(lo, hi), math.max(lo, hi)).toDouble();
    return ev.clamp(lo, hi).toDouble();
  }

  /// EV that puts [f]'s lit skin at [lStar].
  static double _evFor(FaceRead f, double lStar) {
    final y = _yOf(lStar);
    return _log2(math.max(y, 1e-5) / math.max(f.skin.litY, 1e-5));
  }

  static double _yOf(double lStar) {
    final t = (lStar + 16) / 116;
    return t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
  }

  /// Histogram opinion: the median against a scene-adaptive key with an
  /// accept band (research 01 §6.4), gated by the key flags.
  static double _globalEv(FrameMeasure m, EnhanceScene scene, double keyScale) {
    if (scene.highKey || scene.lowKey) return 0;
    final median = math.max(m.medianY, 1e-4);
    if (median >= _C.bandLowY * keyScale && median <= _C.bandHighY * keyScale) {
      return 0;
    }
    final key = (sceneKey(m) * keyScale)
        .clamp(_C.targetLowY * keyScale, _C.targetHighY * keyScale)
        .toDouble();
    return _log2(key / median);
  }

  /// Scene-adaptive key (Reinhard 2002 auto-key, damped).
  static double sceneKey(FrameMeasure m) {
    final lmin = math.max(m.yP1, 1e-4);
    final lmax = m.yP99;
    if (lmax <= lmin * math.sqrt2) return _C.keyBase;
    final lavg = m.lAvg.clamp(lmin, lmax);
    final f =
        (2 * _log2(lavg) - _log2(lmin) - _log2(lmax)) /
        (_log2(lmax) - _log2(lmin));
    final key = _C.keyBase * math.pow(4, _C.keyAdaptivity * f);
    return key.clamp(_C.keyMin, _C.keyMax).toDouble();
  }

  /// Highlight guard: the largest positive EV ≤ [ev] that newly clips at
  /// most [limit] of [px] (linear, measured after white balance).
  static double guardClipping(LinearPixels px, double ev, double limit) {
    if (ev <= 0) return ev;
    final allowed = math.max(limit, 2 * _clippedAt(px, 0));
    if (_clippedAt(px, ev) <= allowed) return ev;
    var lo = ev / 2, hi = ev;
    for (var i = 0; i < 10; i++) {
      final mid = (lo + hi) / 2;
      if (_clippedAt(px, mid) <= allowed) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static double _clippedAt(LinearPixels px, double ev) {
    final gain = math.pow(2, ev).toDouble();
    final limit = srgbToLinear(_C.clipEncoded) / gain;
    final d = px.rgb;
    var n = 0;
    for (var o = 0; o < d.length; o += 3) {
      if (d[o] >= limit || d[o + 1] >= limit || d[o + 2] >= limit) n++;
    }
    return n / px.pixelCount;
  }
}
