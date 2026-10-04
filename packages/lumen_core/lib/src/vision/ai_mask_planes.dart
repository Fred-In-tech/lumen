import 'dart:math' as math;
import 'dart:typed_data';

import '../model/mask.dart';
import '../render/mask_rasterizer.dart';
import 'guided_filter.dart';
import 'segmentation.dart';

/// One stored AI coverage raster. Several mask kinds may share one.
enum AiRaster {
  /// 1 − background: every person (Selfie Multiclass has no instances).
  people,
  background,
  faceSkin,
  hair,
  clothes;

  /// The raster a mask kind reads, or null when no on-device model makes
  /// it (sky) or the kind is not an AI kind.
  static AiRaster? forKind(MaskKind kind) => switch (kind) {
    MaskKind.subject || MaskKind.person => people,
    MaskKind.background => background,
    MaskKind.faceSkin => faceSkin,
    MaskKind.sky ||
    MaskKind.linear ||
    MaskKind.radial ||
    MaskKind.brush ||
    MaskKind.unsupported => null,
  };
}

final _unsafe = RegExp(r'[^A-Za-z0-9_-]');
final _ref = RegExp(r'^([A-Za-z]+)\.([A-Za-z0-9_-]+)$');

/// File-safe `maskRef` of [raster] made by [modelKey] (`id@version`), e.g.
/// `people.selfie_multiclass_256-1`; stored as `<maskRef>.png`.
String aiMaskRef(AiRaster raster, String modelKey) =>
    '${raster.name}.${modelKey.replaceAll(_unsafe, '-')}';

/// Parses an [aiMaskRef]; null for refs this version did not make.
({AiRaster raster, String model})? parseAiMaskRef(String ref) {
  final m = _ref.firstMatch(ref);
  if (m == null) return null;
  final raster = AiRaster.values.where((r) => r.name == m.group(1));
  return raster.isEmpty ? null : (raster: raster.single, model: m.group(2)!);
}

/// Composited, edge-refined 8-bit coverage planes on the mask grid.
class AiMaskPlanes {
  AiMaskPlanes(
    this.width,
    this.height,
    Map<AiRaster, Uint8List> planes, {
    this.faceCropsUsed = 0,
  }) : planes = Map.unmodifiable(planes);

  final int width;
  final int height;
  final Map<AiRaster, Uint8List> planes;

  /// Per-face crops that passed the agreement check and were composited.
  final int faceCropsUsed;

  MaskRaster raster(AiRaster r) => MaskRaster(
    width,
    height,
    planes[r] ?? (throw ArgumentError('no ${r.name} plane')),
  );
}

/// Edge refinement settings (research 07 §2.2 step 2).
class GuidedFilterParams {
  const GuidedFilterParams({
    this.radius,
    this.eps = 1e-3,
    this.contrast = 0.15,
  });

  /// Window radius in grid pixels; null = two whole-image model cells
  /// (2 × grid long edge / 256, at least 2). The window must span the
  /// bilinear transition (about two cells) for the edge to snap.
  final int? radius;
  final double eps;

  /// After filtering, coverage is remapped with smoothstep(c, 1 − c): the
  /// guided filter puts the edge on the photo edge but leaves low-amplitude
  /// tails (the coarse mask's mean on each side); this removes that halo.
  /// Symmetric, so people and background stay complementary. 0 = off.
  final double contrast;

  int radiusFor(int gridLongEdge) =>
      radius ?? math.max(2, (2 * gridLongEdge / 256).round());
}

/// Builds the AI planes on a [gridWidth]×[gridHeight] grid spanning a
/// [sourceWidth]×[sourceHeight] image: each class is the [whole]-image
/// pass, replaced inside each per-face [faces] crop (feathered at the crop
/// border). A crop that sees much less of a person at its centre than the
/// whole pass (crop < [minCropAgreement] × whole, see [personAgreement])
/// is dropped rather than allowed to erase a face. Then every plane is
/// refined with a guided filter against
/// [guide] (grid luma, 0..1; null skips refinement) and contrast-shaped
/// (see [GuidedFilterParams.contrast]). people = 1 − background.
AiMaskPlanes composeAiMasks({
  required int gridWidth,
  required int gridHeight,
  required int sourceWidth,
  required int sourceHeight,
  required SegmentationView whole,
  List<SegmentationView> faces = const [],
  Float32List? guide,
  GuidedFilterParams refine = const GuidedFilterParams(),
  double feather = 0.1,
  double minCropAgreement = 0.8,
}) {
  final used = [
    for (final f in faces)
      if (personAgreement(whole, f) case (final c, final w)
          when c >= minCropAgreement * w)
        f,
  ];
  const classes = [
    SelfieClass.background,
    SelfieClass.faceSkin,
    SelfieClass.hair,
    SelfieClass.clothes,
  ];
  final n = gridWidth * gridHeight;
  final planes = [for (final _ in classes) Float32List(n)];
  final sx = sourceWidth / gridWidth, sy = sourceHeight / gridHeight;
  final w = List<double>.filled(used.length, 0);
  final v = List<double>.filled(classes.length, 0);
  final local = List<double>.filled(classes.length, 0);
  final tmp = List<double>.filled(classes.length, 0);
  for (var gy = 0; gy < gridHeight; gy++) {
    final y = (gy + 0.5) * sy;
    for (var gx = 0; gx < gridWidth; gx++) {
      final x = (gx + 0.5) * sx;
      final i = gy * gridWidth + gx;
      whole.sampleInto(x, y, classes, v);
      var wMax = 0.0, wSum = 0.0;
      for (var f = 0; f < used.length; f++) {
        w[f] = used[f].weight(x, y, feather: feather);
        wMax = math.max(wMax, w[f]);
        wSum += w[f];
      }
      if (wSum > 0) {
        local.fillRange(0, local.length, 0);
        for (var f = 0; f < used.length; f++) {
          if (w[f] <= 0) continue;
          used[f].sampleInto(x, y, classes, tmp);
          for (var k = 0; k < classes.length; k++) {
            local[k] += w[f] * tmp[k];
          }
        }
        for (var k = 0; k < classes.length; k++) {
          v[k] = v[k] * (1 - wMax) + local[k] / wSum * wMax;
        }
      }
      for (var k = 0; k < classes.length; k++) {
        planes[k][i] = v[k];
      }
    }
  }
  final refined = guide == null
      ? planes
      : guidedFilterPlanes(
          guide,
          planes,
          gridWidth,
          gridHeight,
          radius: refine.radiusFor(math.max(gridWidth, gridHeight)),
          eps: refine.eps,
        );
  final c = guide == null ? 0.0 : refine.contrast;
  Uint8List bytes(Float32List p, {bool invert = false}) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      var v = (invert ? 1 - p[i] : p[i]).clamp(0.0, 1.0);
      if (c > 0) {
        final t = ((v - c) / (1 - 2 * c)).clamp(0.0, 1.0);
        v = t * t * (3 - 2 * t);
      }
      out[i] = (v * 255).round();
    }
    return out;
  }

  return AiMaskPlanes(gridWidth, gridHeight, faceCropsUsed: used.length, {
    AiRaster.background: bytes(refined[0]),
    AiRaster.people: bytes(refined[0], invert: true),
    AiRaster.faceSkin: bytes(refined[1]),
    AiRaster.hair: bytes(refined[2]),
    AiRaster.clothes: bytes(refined[3]),
  });
}
