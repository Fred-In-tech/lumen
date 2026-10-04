/// Per-parameter backdrop textures, built on the CPU from a [BackdropBase]
/// and sampled identically by `backdrop.frag` and [applyBackdrop]. Rebuild
/// when the mode, edge shift/feather, blur amount or backdrop image change;
/// colours, gradient, fit, spill and match are uniforms only.
///
/// | texture | grid | R | G | B |
/// |---|---|---|---|---|
/// | `matte` | matte | coverage | edge band (spill) | depth (blur) |
/// | `fill` | plate | old background, subject filled (sRGB) | | |
/// | `plateA` | plate / image | near blur, or the backdrop image | | |
/// | `plateB` | plate | far blur | | |
///
/// Every texture is RGBA8 with A = 255, sampled with a manual bilinear.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/rgb.dart';
import '../color/srgb.dart';
import '../model/backdrop_change.dart';
import '../render/aux_maps.dart';
import '../render/rgba_buffer.dart';
import '../vision/guided_filter.dart';
import 'backdrop_base.dart';
import 'backdrop_filters.dart';

export 'backdrop_filters.dart' show ByteTexture;

/// Backdrop images are cached at most this long edge.
const int kBackdropImageLongEdge = 2048;

/// What backdrop textures depend on (see [BackdropAssets.keyOf]); `plates`
/// is 0 (none: colour modes), 1 (blur) or 2 (image).
typedef BackdropAssetKey = ({
  int plates,
  double blur,
  double shift,
  double feather,
});

final ByteTexture _blank = (width: 1, height: 1, rgba: Uint8List(4));

class BackdropAssets {
  BackdropAssets._(
    this.base,
    this.matte,
    this.fill,
    this.plateA,
    this.plateB,
    this.plateMean,
    this.key,
    this.image,
  );

  /// What the textures depend on in a [BackdropChange]: rebuild when
  /// `keyOf(next) != assets.key` or the backdrop image changes.
  static BackdropAssetKey keyOf(BackdropChange b) => (
    plates: switch (b.mode) {
      BackdropMode.blur => 1,
      BackdropMode.image => 2,
      _ => 0,
    },
    blur: b.mode == BackdropMode.blur ? b.blur : 0.0,
    shift: b.edgeShift,
    feather: b.feather,
  );

  /// True when these (maybe stale) textures can stand in for [b] until its
  /// own are built: colour modes only need the matte; blur and image need
  /// their plates.
  bool canRender(BackdropChange b) =>
      !b.isNone &&
      switch (b.mode) {
        BackdropMode.none => false,
        BackdropMode.color || BackdropMode.gradient => true,
        BackdropMode.blur ||
        BackdropMode.image => keyOf(b).plates == key.plates,
      };

  /// True when these textures render [b] with [image] exactly.
  bool fits(BackdropChange b, RgbaBuffer? image) =>
      keyOf(b) == key &&
      (b.mode != BackdropMode.image || identical(image, this.image));

  factory BackdropAssets.build(
    BackdropBase base,
    BackdropChange b, {
    RgbaBuffer? image,
  }) {
    final mw = base.matteWidth, mh = base.matteHeight;
    final le = math.max(mw, mh);
    final a = _shifted(base.alpha, b.edgeShift / 100);
    final f = b.feather / 100;
    final rf = (f * f * 0.008 * le).round();
    final soft = rf > 0 ? boxMean(boxMean(a, mw, mh, rf), mw, mh, rf) : a;
    final band = boxMean(
      _inverse(soft),
      mw,
      mh,
      math.max(1, (0.01 * le).round()),
    );
    final blurMode = b.mode == BackdropMode.blur;
    final rd = math.max(1, (0.05 * le).round());
    final near = blurMode
        ? boxMean(boxMean(soft, mw, mh, rd), mw, mh, rd)
        : null;
    final matte = Uint8List(mw * mh * 4);
    for (var i = 0; i < mw * mh; i++) {
      matte[4 * i] = _byte(soft[i]);
      matte[4 * i + 1] = soft[i] > 0.02 ? _byte(2 * band[i]) : 0;
      matte[4 * i + 2] = near == null ? 0 : _byte(1 - 2 * near[i]);
      matte[4 * i + 3] = 255;
    }
    final pw = base.plateWidth, ph = base.plateHeight;
    final fill = base.fill;
    var plateA = _blank, plateB = _blank;
    var mean = base.oldBackgroundMean;
    switch (b.mode) {
      case BackdropMode.blur:
        final rb = b.blur / 100 * 0.035 * math.max(pw, ph);
        ByteTexture blurred(double sigma) {
          final k = math.max(0, (sigma / 1.7).round());
          return (
            width: pw,
            height: ph,
            rgba: encodePlanes(
              blur3(base.fillR, pw, ph, k),
              blur3(base.fillG, pw, ph, k),
              blur3(base.fillB, pw, ph, k),
            ),
          );
        }
        plateA = blurred(0.35 * rb);
        plateB = blurred(rb);
      case BackdropMode.image:
        if (image != null) {
          final small = AuxMaps.proxy(image, longEdge: kBackdropImageLongEdge);
          plateA = (width: small.width, height: small.height, rgba: small.data);
          mean = _meanLinear(small);
        }
      case BackdropMode.color:
      case BackdropMode.gradient:
      case BackdropMode.none:
        break;
    }
    return BackdropAssets._(
      base,
      (width: mw, height: mh, rgba: matte),
      fill,
      plateA,
      plateB,
      mean,
      keyOf(b),
      b.mode == BackdropMode.image ? image : null,
    );
  }

  final BackdropBase base;
  final ByteTexture matte;
  final ByteTexture fill;
  final ByteTexture plateA;
  final ByteTexture plateB;

  /// Mean colour (linear) of the backdrop image (image mode), else of the
  /// old background.
  final Rgb plateMean;

  /// [keyOf] the change these textures were built for.
  final BackdropAssetKey key;

  /// The backdrop image they were built from (image mode), by identity.
  final RgbaBuffer? image;

  /// Edge shift: s > 0 spreads the matte, s < 0 chokes it (identity at 0).
  static Float32List _shifted(Float32List a, double s) {
    if (s == 0) return a;
    final c = 0.5 - 0.45 * s, k = 1 / (1 - 0.9 * s.abs());
    final out = Float32List(a.length);
    for (var i = 0; i < a.length; i++) {
      final v = (a[i] - c) * k + 0.5;
      out[i] = v < 0 ? 0 : (v > 1 ? 1 : v);
    }
    return out;
  }

  static Float32List _inverse(Float32List a) {
    final out = Float32List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = 1 - a[i];
    }
    return out;
  }

  /// 0..1 → 0..255 (clamped, rounded).
  static int _byte(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).round());

  static Rgb _meanLinear(RgbaBuffer img) {
    var r = 0.0, g = 0.0, b = 0.0;
    final lut = kSrgbByteToLinear, d = img.data, n = img.pixelCount;
    for (var i = 0; i < n; i++) {
      r += lut[d[4 * i]];
      g += lut[d[4 * i + 1]];
      b += lut[d[4 * i + 2]];
    }
    return Rgb(r / n, g / n, b / n);
  }
}
