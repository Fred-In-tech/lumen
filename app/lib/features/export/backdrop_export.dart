import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';

/// Background-swap inputs of a stored photo for export and batch: the
/// person/hair rasters (the on-device segmentation, run on demand) and the
/// backdrop image from the patch store.
BackdropInputsLoader backdropInputsLoader({
  required AiMaskSource? source,
  required AiMaskRasterLoader? loader,
  required PatchStoreGetter? patches,
}) => (assetId, change) async {
  if (change.isNone) return kNoBackdropInputs;
  final rasters = await loadBackdropRasters(source, loader, assetId);
  RgbaBuffer? image;
  if (change.mode == BackdropMode.image &&
      change.imageRef.isNotEmpty &&
      patches != null) {
    image = await (await patches()).load(assetId, change.imageRef);
  }
  return (people: rasters.people, hair: rasters.hair, image: image);
};
