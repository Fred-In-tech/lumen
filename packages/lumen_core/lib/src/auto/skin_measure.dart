import 'dart:math' as math;
import 'dart:typed_data';

import '../color/cielab.dart';
import '../color/srgb.dart';
import '../model/face_analysis.dart';
import 'enhance_constants.dart';
import 'enhance_pixels.dart';

typedef _C = EnhanceConstants;

double _log2(double x) => math.log(x) / math.ln2;

/// The skin pixels of one face on the solver proxy.
///
/// Built once from the unedited proxy and reused on every render of it, so
/// each measurement reads the same pixels. Holds pixel indices only: no face
/// geometry leaves the solver.
class SkinRegion {
  const SkinRegion({
    required this.pixels,
    required this.areaFraction,
    required this.widthFraction,
    required this.weight,
  });

  /// Row-major pixel indices of diffuse skin.
  final Int32List pixels;

  /// Face box area / frame area.
  final double areaFraction;

  /// Face box width / frame width.
  final double widthFraction;

  /// Share of this face among all faces (√area, sums to 1).
  final double weight;
}

/// Finds diffuse skin inside face boxes (research 09 §2.2 `skinD`).
abstract final class SkinRegions {
  /// One region per usable face of [faces] (normalised boxes), largest
  /// first. Faces that are too small or hold no coherent skin are skipped.
  static List<SkinRegion> locate(LinearPixels px, List<FaceBox> faces) {
    final found = <(Int32List, FaceBox)>[];
    for (final box in faces) {
      if (box.width * px.width < _C.minFacePixels) continue;
      final pixels = _skinOf(px, box);
      if (pixels.length >= _C.minSkinSamples) found.add((pixels, box));
    }
    double root(FaceBox b) => math.sqrt(b.width * b.height);
    found.sort((a, b) => root(b.$2).compareTo(root(a.$2)));
    final total = found.fold(0.0, (s, f) => s + root(f.$2));
    return [
      for (final (pixels, box) in found)
        SkinRegion(
          pixels: pixels,
          areaFraction: box.width * box.height,
          widthFraction: box.width,
          weight: root(box) / total,
        ),
    ];
  }

  /// Per-pixel mask (1 = skin of any face) for [regions].
  static Uint8List mask(int pixelCount, List<SkinRegion> regions) {
    final out = Uint8List(pixelCount);
    for (final r in regions) {
      for (final i in r.pixels) {
        out[i] = 1;
      }
    }
    return out;
  }

  static Int32List _skinOf(LinearPixels px, FaceBox box) {
    final w = px.width, h = px.height, d = px.rgb;
    final cx = box.centerX * w, cy = box.centerY * h;
    final bw = box.width * w, bh = box.height * h;
    final rx = bw * _C.skinRadiusX, ry = bh * _C.skinRadiusY;
    final sx = bw * _C.seedRadiusX, sy = bh * _C.seedRadiusY;
    final x0 = math.max(0, (cx - rx).floor());
    final x1 = math.min(w - 1, (cx + rx).ceil());
    final y0 = math.max(0, (cy - ry).floor());
    final y1 = math.min(h - 1, (cy + ry).ceil());
    // Seed: the centre of the face (cheeks, nose) gives the skin colour.
    final seedY = <double>[], seedRg = <double>[], seedBg = <double>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = (x + 0.5 - cx) / sx, dy = (y + 0.5 - cy) / sy;
        if (dx * dx + dy * dy > 1) continue;
        final o = (y * w + x) * 3;
        final r = d[o], g = d[o + 1], b = d[o + 2];
        final lum = luminanceOf(r, g, b);
        if (lum < _C.darkY || _clipped(r, g, b)) continue;
        seedY.add(lum);
        seedRg.add(_log2(math.max(r, 1e-5) / math.max(g, 1e-5)));
        seedBg.add(_log2(math.max(b, 1e-5) / math.max(g, 1e-5)));
      }
    }
    if (seedY.length < 4) return Int32List(0);
    final my = _median(seedY), mrg = _median(seedRg), mbg = _median(seedBg);
    final out = <int>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
        if (dx * dx + dy * dy > 1) continue;
        final i = y * w + x, o = i * 3;
        final r = d[o], g = d[o + 1], b = d[o + 2];
        final lum = luminanceOf(r, g, b);
        if (lum < my * _C.skinYLow || lum > my * _C.skinYHigh) continue;
        if (lum < _C.darkY || _clipped(r, g, b)) continue;
        final drg = _log2(math.max(r, 1e-5) / math.max(g, 1e-5)) - mrg;
        final dbg = _log2(math.max(b, 1e-5) / math.max(g, 1e-5)) - mbg;
        if (drg * drg + dbg * dbg >
            _C.skinChromaDistance * _C.skinChromaDistance) {
          continue;
        }
        out.add(i);
      }
    }
    return Int32List.fromList(out);
  }

  static bool _clipped(double r, double g, double b) =>
      linearToSrgb(math.max(r, math.max(g, b))) >= _C.clipEncoded;

  static double _median(List<double> v) {
    v.sort();
    return v[v.length ~/ 2];
  }
}

/// What one face's skin looks like in one frame.
class SkinReading {
  const SkinReading._({
    required this.litY,
    required this.hot,
    required this.contrast,
    required this.a,
    required this.m,
    required this.hue,
    required this.chroma,
  });

  /// Reads [region] in [px] (the proxy the region was located on, or any
  /// render of it).
  factory SkinReading.of(LinearPixels px, SkinRegion region) {
    final d = px.rgb;
    final n = region.pixels.length;
    final order = List<int>.generate(n, (k) => k);
    final ys = Float64List(n);
    final maxEnc = Float64List(n);
    for (var k = 0; k < n; k++) {
      final o = region.pixels[k] * 3;
      ys[k] = luminanceOf(d[o], d[o + 1], d[o + 2]);
      maxEnc[k] = linearToSrgb(math.max(d[o], math.max(d[o + 1], d[o + 2])));
    }
    order.sort((p, q) {
      final c = ys[p].compareTo(ys[q]);
      return c != 0 ? c : p.compareTo(q);
    });
    final from = (n * _C.litLow).floor();
    final to = math.max(from + 1, (n * _C.litHigh).ceil());
    var r = 0.0, g = 0.0, b = 0.0;
    for (var k = from; k < to; k++) {
      final o = region.pixels[order[k]] * 3;
      r += d[o];
      g += d[o + 1];
      b += d[o + 2];
    }
    final count = to - from;
    r /= count;
    g /= count;
    b /= count;
    final sorted = Float64List.fromList(maxEnc)..sort();
    final lab = linearSrgbToLab(
      r.clamp(0.0, 1.0),
      g.clamp(0.0, 1.0),
      b.clamp(0.0, 1.0),
    );
    double yAt(double q) => ys[order[((n - 1) * q).round()]];
    return SkinReading._(
      litY: luminanceOf(r, g, b),
      hot: sorted[((n - 1) * 0.98).round()],
      contrast: lStarFromY(yAt(0.95)) - lStarFromY(yAt(0.05)),
      a: _log2(math.max(r, 1e-5) / math.max(b, 1e-5)),
      m: _log2(math.max(g, 1e-5) / math.sqrt(math.max(r * b, 1e-10))),
      hue: _hue601(linearToSrgb(r), linearToSrgb(g), linearToSrgb(b)),
      chroma: lab.chroma,
    );
  }

  /// Mean luminance of the lit diffuse side (40th–80th percentile).
  final double litY;

  /// P98 of the brightest encoded channel over diffuse skin.
  final double hot;

  /// P95 − P5 of skin L* (face modelling: high means hard light).
  final double contrast;

  /// log2(R/B) and log2(G/√RB) of lit skin (exposure-independent).
  final double a;
  final double m;

  /// BT.601 hue angle of lit skin in degrees (the vectorscope skin line).
  final double hue;

  /// CIELAB chroma C* of lit skin.
  final double chroma;

  /// L* of the lit diffuse side.
  double get lStar => lStarFromY(litY.clamp(0.0, 1.0));

  static double _hue601(double r, double g, double b) {
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    final h = math.atan2((r - y) * 0.713, (b - y) * 0.564) * 180 / math.pi;
    return h < 0 ? h + 360 : h;
  }
}
