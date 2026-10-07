import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('RetouchTiles');

/// Face tiles of a photo cropped from its full-resolution pixel source
/// (`planFaceTiles` on the original's size), so each face is analysed at
/// up to `kTileTargetIod` px of IOD instead of the ~2560 px decode.
typedef FaceTiles = List<FaceTileImage>;

/// Faces of [faces] that a visible heal op touches: their tiles come from
/// the healed analysis decode instead (the heal is drawn there).
Set<String> facesWithHeals(List<HealOp> ops, FaceAnalysis faces) => {
  for (final f in faces.faces)
    if (healOpsOnFaces(
      ops,
      FaceAnalysis(
        imageWidth: faces.imageWidth,
        imageHeight: faces.imageHeight,
        modelVersion: faces.modelVersion,
        faces: [f],
      ),
    ).isNotEmpty)
      f.id,
};

/// Decodes [assetId]'s pixel source at full size and crops the planned
/// tile of every face of [faces] except those in [skip]. Never throws:
/// on any failure the result is empty and the maps fall back to tiles
/// resampled from the analysis decode.
Future<FaceTiles> loadFaceTiles(
  CatalogRepository catalog,
  String assetId,
  FaceAnalysis faces, {
  Set<String> skip = const {},
}) async {
  if (faces.faces.every((f) => skip.contains(f.id))) return const [];
  ui.Image? image;
  try {
    image = await decodePhoto(await catalog.readPixelSource(assetId));
    final plans = planFaceTiles(faces, image.width, image.height);
    return [
      for (final p in plans)
        if (!skip.contains(p.faceId))
          FaceTileImage(p, await cropTile(image, p)),
    ];
  } on Exception catch (e) {
    _log.warning('full-resolution face tiles unavailable for $assetId: $e');
    return const [];
  } finally {
    image?.dispose();
  }
}

/// [plan]'s window of [image] (whose size `planFaceTiles` was given),
/// drawn at the tile's size on the GPU (mipmapped, so a downscale averages
/// instead of skipping pixels).
Future<RgbaBuffer> cropTile(ui.Image image, FaceTilePlan plan) async {
  final kx = image.width / plan.gridW, ky = image.height / plan.gridH;
  final src = ui.Rect.fromLTWH(
    plan.window.x0 * kx,
    plan.window.y0 * ky,
    plan.width * kx,
    plan.height * ky,
  );
  final dst = ui.Rect.fromLTWH(
    0,
    0,
    plan.width.toDouble(),
    plan.height.toDouble(),
  );
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    src,
    dst,
    ui.Paint()
      ..filterQuality = math.max(kx, ky) > 1.01
          ? ui.FilterQuality.medium
          : ui.FilterQuality.none,
  );
  final picture = recorder.endRecording();
  final ui.Image tile;
  try {
    tile = await picture.toImage(plan.width, plan.height);
  } finally {
    picture.dispose();
  }
  try {
    return await rgbaFromImage(tile);
  } finally {
    tile.dispose();
  }
}
