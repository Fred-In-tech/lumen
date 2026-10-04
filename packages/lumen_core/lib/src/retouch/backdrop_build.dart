/// Builds [BackdropMaps] once per photo from the source and the person
/// (and hair) rasters of the vision pipeline, plus the clothes raster for
/// the clothing cleanup (`clothes_maps.dart`); each part only when its
/// sliders are set. Pure and isolate-safe.
///
/// 1. Person matte P: the people raster, resampled to the backdrop grid
///    and refined against L with a small guided filter.
/// 2. Solid check on the core backdrop (matte ≈ 1, a guard band away from
///    the subject): robust spread of `G − E0` (σ1 image vs a 2 % smooth)
///    in L and chroma. Textured backdrops disable every backdrop effect.
/// 3. E: subject and defects (robust outliers) are push-pull filled from
///    clean backdrop, then a guided filter (r = 2 % of the long edge)
///    smooths dust, scuffs, seams, small wrinkles and banding but keeps
///    real backdrop edges and the light falloff.
/// 4. U: the filled backdrop at 5 % of the long edge (falloff, hotspots);
///    the Unify target is the median backdrop colour.
/// 5. Weights: clean (matte minus a guard band at the subject edge),
///    the raw matte (Unify) and stray hairs (`backdrop_strays.dart`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../render/aux_maps.dart';
import '../render/mask_rasterizer.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_maps.dart';
import 'backdrop_strays.dart';
import 'clothes_maps.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'push_pull.dart';
import 'retouch_maps.dart' show encodeSignedDithered;

/// Image-scope grid long edge (the atlas is 3 × 2 tiles of this grid).
const int kBackdropLongEdge = 1024;

/// Clean guard band at the subject edge (fraction of the long edge).
const double kBackdropGuardFrac = 0.008;

/// E: guided filter radius (fraction of the long edge) and ε (OkLab L²).
const double kBackdropEstimateFrac = 0.02;
const double kBackdropEstimateEps = 9e-4;

/// U: illumination field σ (fraction of the long edge).
const double kBackdropLightFrac = 0.05;

/// Solid backdrop: robust spread (1.4826·MAD) of `G − E0` below these.
const double kSolidMadL = 0.012;
const double kSolidMadC = 0.008;

/// The Unify matte is `smoothstep(lo, hi, 1 − P)`.
const double kUnifyMatteLo = 0.15;
const double kUnifyMatteHi = 0.85;

/// Core backdrop needed (fraction of the frame).
const double kMinBackdropFraction = 0.08;

/// A backdrop pixel is a defect (filled before E) when `|G − E0|` exceeds
/// max(this, 4·MAD).
const double kDefectFloorL = 0.02;

/// Grain soft-clip τ = max(floor, k·σ_grain).
const double kGrainTauSigmas = 3.0;
const double kGrainTauFloorL = 0.012;
const double kGrainTauFloorC = 0.006;

/// Inputs for the image-scope maps (8-bit coverage on any grid with the
/// source's aspect, e.g. the 1024-px AI mask grid): the person (and hair)
/// rasters for the backdrop, the clothes raster for clothing cleanup.
/// [missing] = backdrop requested but no person raster
/// ([BackdropState.noMatte]).
class BackdropInput {
  const BackdropInput({
    this.people,
    this.hair,
    this.clothes,
    this.wantsBackdrop = true,
    this.wantsClothes = false,
  });

  static const missing = BackdropInput();

  final MaskRaster? people;
  final MaskRaster? hair;
  final MaskRaster? clothes;
  final bool wantsBackdrop;
  final bool wantsClothes;
}

/// Computes the image-scope maps of [source] ([input] null → nothing
/// requested): the backdrop part and the clothes part, each only when
/// wanted and possible, on one grid and one atlas.
BackdropMaps computeBackdropMaps(RgbaBuffer source, BackdropInput? input) {
  if (input == null) return BackdropMaps.none(BackdropState.notRequested);
  var state = !input.wantsBackdrop
      ? BackdropState.notRequested
      : (input.people == null ? BackdropState.noMatte : BackdropState.ready);
  var clothesState = !input.wantsClothes
      ? ClothesState.notRequested
      : (input.clothes == null ? ClothesState.noMatte : ClothesState.ready);
  if (state != BackdropState.ready && clothesState != ClothesState.ready) {
    return BackdropMaps.none(state, clothes: clothesState);
  }
  final srcLong = math.max(source.width, source.height);
  final grid = AuxMaps.proxy(
    source,
    longEdge: math.min(kBackdropLongEdge, srcLong),
  );
  final w = grid.width, h = grid.height;
  final lab = LabPlanes.fromRgba(grid, MapRect(0, 0, w, h));
  final g1 = lab.mapChannels((c) => gaussianBlur(c, w, h, 1.0));
  final atlas = _Atlas(w, h);
  _BackdropStats? stats;
  if (state == BackdropState.ready) {
    final r = _backdrop(lab, g1, input, atlas, w, h);
    state = r.state;
    stats = r.stats;
  }
  if (clothesState == ClothesState.ready) {
    final cloth = _refined(lab, input.clothes!, w, h);
    final planes = computeClothes(lab, g1, cloth, w, h);
    if (planes == null) {
      clothesState = ClothesState.noClothes;
    } else {
      atlas.signed(2, 0, planes.fold, kClothesFoldRange, 21);
      atlas.signed(2, 1, planes.lint, kLintRange, 22);
    }
  }
  if (state != BackdropState.ready && clothesState != ClothesState.ready) {
    return BackdropMaps.none(state, clothes: clothesState);
  }
  return BackdropMaps(
    width: w,
    height: h,
    atlas: atlas.bytes,
    state: state,
    clothesState: clothesState,
    medianL: stats?.medianL ?? 0,
    medianA: stats?.medianA ?? 0,
    medianB: stats?.medianB ?? 0,
    tauL: stats?.tauL ?? kGrainTauFloorL,
    tauC: stats?.tauC ?? kGrainTauFloorC,
    textureMad: stats?.mad ?? 0,
  );
}

/// A raster resampled to the grid and refined against L.
Float32List _refined(LabPlanes lab, MaskRaster r, int w, int h) {
  final raw = resampleRaster(r, w, h);
  final out = guidedFilter(lab.l, [raw], w, h, 2, 1e-3).first;
  for (var i = 0; i < out.length; i++) {
    out[i] = clamp01(out[i]);
  }
  return out;
}

typedef _BackdropStats = ({
  double medianL,
  double medianA,
  double medianB,
  double tauL,
  double tauC,
  double mad,
});

/// The 3×2-tile atlas being built (signed tiles start at 128 = 0).
class _Atlas {
  _Atlas(this.w, this.h)
    : bytes = Uint8List(4 * kImageAtlasColumns * kImageAtlasRows * w * h) {
    for (var ty = 0; ty < kImageAtlasRows; ty++) {
      for (var y = 0; y < h; y++) {
        for (var tx = 0; tx < kImageAtlasColumns; tx++) {
          final v = tx == 2 ? 128 : 0;
          for (var x = 0; x < w; x++) {
            final o = _offset(tx, ty, x, y);
            bytes[o] = v;
            bytes[o + 1] = v;
            bytes[o + 2] = v;
            bytes[o + 3] = 255;
          }
        }
      }
    }
  }

  final int w;
  final int h;
  final Uint8List bytes;

  int _offset(int tx, int ty, int x, int y) =>
      ((ty * h + y) * kImageAtlasColumns * w + tx * w + x) * 4;

  /// OkLab planes as dithered sRGB into tile ([tx], [ty]).
  void srgb(LabPlanes planes, int tx, int ty, int seed) {
    final all = Int8List(w * h);
    final tex = Uint8List(4 * w * h);
    planes.writeSrgb(tex, w, all, 0, seed: seed);
    for (var y = 0; y < h; y++) {
      final dst = _offset(tx, ty, 0, y);
      bytes.setRange(dst, dst + 4 * w, tex, y * w * 4);
    }
  }

  /// Three 0..1 planes as bytes into tile ([tx], [ty]).
  void unit(List<Float32List> planes, int tx, int ty) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = _offset(tx, ty, x, y), i = y * w + x;
        for (var c = 0; c < 3; c++) {
          bytes[o + c] = _byte(planes[c][i]);
        }
      }
    }
  }

  /// Three signed planes into tile ([tx], [ty]), dithered (seeded).
  void signed(
    int tx,
    int ty,
    List<Float32List> planes,
    List<double> range,
    int seed,
  ) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = _offset(tx, ty, x, y), i = y * w + x;
        for (var c = 0; c < 3; c++) {
          bytes[o + c] = encodeSignedDithered(
            planes[c][i],
            range[c],
            ditherAt(x, y, seed, c),
          );
        }
      }
    }
  }
}

/// The backdrop part: solid check, E, U, weights and statistics.
({BackdropState state, _BackdropStats? stats}) _backdrop(
  LabPlanes lab,
  LabPlanes g1,
  BackdropInput input,
  _Atlas atlas,
  int w,
  int h,
) {
  final n = w * h, long = math.max(w, h);
  // 1. Person matte, refined against L.
  final p = _refined(lab, input.people!, w, h);
  final hair = input.hair == null ? null : resampleRaster(input.hair!, w, h);
  // Core backdrop: clearly background, a guard band away from the subject.
  final guard = math.max(1, (kBackdropGuardFrac * long).round());
  final subject = Float32List(n);
  for (var i = 0; i < n; i++) {
    subject[i] = smoothstep(0.05, 0.3, p[i]);
  }
  final grown = dilate(subject, w, h, guard);
  final core = Float32List(n);
  var area = 0.0;
  for (var i = 0; i < n; i++) {
    core[i] = grown[i] > 0 ? 0 : smoothstep(0.9, 1.0, 1 - p[i]);
    area += core[i];
  }
  if (area < kMinBackdropFraction * n) {
    return (state: BackdropState.tooLittleBackdrop, stats: null);
  }
  // 2. Solid check.
  final r0 = math.max(1, (kBackdropEstimateFrac * long).round());
  final den = _blur3(core, w, h, r0);
  final e0 = g1.mapChannels((c) => _normConv(c, core, den, w, h, r0));
  final resL = Float32List(n), resC = Float32List(n), fine = Float32List(n);
  for (var i = 0; i < n; i++) {
    resL[i] = g1.l[i] - e0.l[i];
    final da = g1.a[i] - e0.a[i], db = g1.b[i] - e0.b[i];
    resC[i] = math.sqrt(da * da + db * db);
    fine[i] = lab.l[i] - g1.l[i];
  }
  final madL = 1.4826 * _maskedMedianAbs(resL, core);
  final madC = 1.4826 * _maskedMedianAbs(resC, core);
  if (madL > kSolidMadL || madC > kSolidMadC) {
    return (state: BackdropState.notSolid, stats: null);
  }
  final grainL = 1.4826 * _maskedMedianAbs(fine, core);
  // 3. E: fill subject + defects from clean backdrop, then edge-aware smooth.
  final defect = math.max(kDefectFloorL, 4 * madL);
  final trust = Float32List(n);
  for (var i = 0; i < n; i++) {
    trust[i] = core[i] >= 0.999 && resL[i].abs() < defect ? 1 : 0;
  }
  final filled = g1.mapChannels((c) => pushPull(c, trust, w, h));
  final e = guidedFilter(
    filled.l,
    filled.channels,
    w,
    h,
    r0,
    kBackdropEstimateEps,
  );
  // 4. Illumination field and the median backdrop colour.
  final lightSigma = kBackdropLightFrac * long;
  final u = filled.mapChannels((c) => lowPass(c, w, h, lightSigma));
  final median = [for (final c in filled.channels) _maskedMedian(c, core)];
  // 5. Weights.
  final guardBlur = gaussianBlur(grown, w, h, guard / 2);
  final strays = strayHairWeights(
    l: lab.l,
    backdropL: e[0],
    person: p,
    hair: hair,
    width: w,
    height: h,
  );
  atlas.srgb(LabPlanes(lab.rect, e[0], e[1], e[2]), 0, 0, kDitherSeedB1 + 10);
  atlas.srgb(g1, 1, 0, kDitherSeedB2 + 10);
  atlas.srgb(u, 0, 1, kDitherSeedB3 + 10);
  final clean = Float32List(n), unify = Float32List(n);
  for (var i = 0; i < n; i++) {
    final bg = 1 - p[i];
    clean[i] = bg * (1 - clamp01(guardBlur[i]));
    // Unify follows the matte itself (no guard: a low-frequency shift must
    // reach the subject edge), contrast-shaped so it does not leak into
    // the subject.
    unify[i] = smoothstep(kUnifyMatteLo, kUnifyMatteHi, bg);
  }
  atlas.unit([clean, unify, strays], 1, 1);
  final grainC = grainL / 2;
  return (
    state: BackdropState.ready,
    stats: (
      medianL: median[0],
      medianA: median[1],
      medianB: median[2],
      tauL: math.max(kGrainTauFloorL, kGrainTauSigmas * grainL),
      tauC: math.max(kGrainTauFloorC, kGrainTauSigmas * grainC),
      mad: madL,
    ),
  );
}

int _ci(int i, int size) => i < 0 ? 0 : (i >= size ? size - 1 : i);

int _byte(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255 + 0.5).toInt());

/// Bilinear resample of an 8-bit raster to `w × h` (0..1).
Float32List resampleRaster(MaskRaster r, int w, int h) {
  final out = Float32List(w * h);
  final sx = r.width / w, sy = r.height / h;
  for (var y = 0; y < h; y++) {
    final py = (y + 0.5) * sy - 0.5;
    final y0 = py.floor(), fy = py - y0;
    final ya = _ci(y0, r.height) * r.width;
    final yb = _ci(y0 + 1, r.height) * r.width;
    for (var x = 0; x < w; x++) {
      final px = (x + 0.5) * sx - 0.5;
      final x0 = px.floor(), fx = px - x0;
      final xa = _ci(x0, r.width), xb = _ci(x0 + 1, r.width);
      final top = r.data[ya + xa] * (1 - fx) + r.data[ya + xb] * fx;
      final bot = r.data[yb + xa] * (1 - fx) + r.data[yb + xb] * fx;
      out[y * w + x] = (top * (1 - fy) + bot * fy) / 255;
    }
  }
  return out;
}

Float32List _blur3(Float32List p, int w, int h, int r) =>
    boxBlur(boxBlur(boxBlur(p, w, h, r), w, h, r), w, h, r);

/// Normalized convolution `blur(c·m) / blur(m)` (three box passes of
/// radius [r], [den] = blur(m)); falls back to [c] where [m] is absent.
Float32List _normConv(
  Float32List c,
  Float32List m,
  Float32List den,
  int w,
  int h,
  int r,
) {
  final num = _blur3(productOf([c, m]), w, h, r);
  for (var i = 0; i < num.length; i++) {
    num[i] = den[i] > 1e-3 ? num[i] / den[i] : c[i];
  }
  return num;
}

/// Gaussian low-pass of [σ] pixels via a coarse grid (O(n)).
Float32List lowPass(Float32List c, int w, int h, double sigma) {
  final k = math.max(1, (sigma / 4).floor());
  if (k == 1) return gaussianBlur(c, w, h, sigma);
  final cw = (w + k - 1) ~/ k, ch = (h + k - 1) ~/ k;
  final small = Float32List(cw * ch), cnt = Float32List(cw * ch);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final j = (y ~/ k) * cw + x ~/ k;
      small[j] += c[y * w + x];
      cnt[j] += 1;
    }
  }
  for (var j = 0; j < small.length; j++) {
    small[j] /= cnt[j];
  }
  final blurred = gaussianBlur(small, cw, ch, sigma / k);
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final py = (y + 0.5) / k - 0.5;
    final y0 = py.floor(), fy = py - y0;
    final ya = _ci(y0, ch) * cw, yb = _ci(y0 + 1, ch) * cw;
    for (var x = 0; x < w; x++) {
      final px = (x + 0.5) / k - 0.5;
      final x0 = px.floor(), fx = px - x0;
      final xa = _ci(x0, cw), xb = _ci(x0 + 1, cw);
      out[y * w + x] =
          (blurred[ya + xa] * (1 - fx) + blurred[ya + xb] * fx) * (1 - fy) +
          (blurred[yb + xa] * (1 - fx) + blurred[yb + xb] * fx) * fy;
    }
  }
  return out;
}

/// Median of `|v|` over pixels with `mask ≥ 0.999` (histogram, O(n)).
double _maskedMedianAbs(Float32List v, Float32List mask) =>
    _histMedian(v, mask, 0, 0.25, abs: true);

/// Median of [v] over pixels with `mask ≥ 0.999` (histogram, O(n)).
double _maskedMedian(Float32List v, Float32List mask) =>
    _histMedian(v, mask, -0.5, 1.5);

/// Histogram median of [v] (or |v|) on [lo, hi] in 8192 bins (values
/// outside are clamped), linearly interpolated inside the median bin.
double _histMedian(
  Float32List v,
  Float32List mask,
  double lo,
  double hi, {
  bool abs = false,
}) {
  const bins = 8192;
  final counts = Int32List(bins);
  final scale = bins / (hi - lo);
  var n = 0;
  for (var i = 0; i < v.length; i++) {
    if (mask[i] < 0.999) continue;
    final x = abs ? v[i].abs() : v[i];
    var b = ((x - lo) * scale).floor();
    b = b < 0 ? 0 : (b >= bins ? bins - 1 : b);
    counts[b]++;
    n++;
  }
  if (n == 0) return 0;
  final half = n / 2;
  var acc = 0;
  for (var b = 0; b < bins; b++) {
    final c = counts[b];
    if (acc + c >= half) {
      return lo + (b + (half - acc) / c) / scale;
    }
    acc += c;
  }
  return hi;
}
