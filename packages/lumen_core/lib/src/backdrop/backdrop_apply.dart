/// One-call backdrop helpers for the CPU renderers and export, and the aux
/// maps of a composite for the GPU graph.
library;

import '../model/backdrop_change.dart';
import '../render/aux_maps.dart';
import '../render/mask_rasterizer.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_assets.dart';
import 'backdrop_base.dart';
import 'backdrop_kernel.dart';

/// [src] with the backdrop [b] composited: builds the matte from [people] ∪
/// [hair] against [src], the textures (with the backdrop [image] in image
/// mode) and applies them. Returns [src] itself when [b] is off or there is
/// no raster (no subject: the pass would replace the whole photo).
RgbaBuffer backdroppedSource(
  RgbaBuffer src,
  BackdropChange b, {
  MaskRaster? people,
  MaskRaster? hair,
  RgbaBuffer? image,
}) {
  if (b.isNone || (people == null && hair == null)) return src;
  final base = BackdropBase.build(src, people: people, hair: hair);
  return applyBackdrop(src, BackdropAssets.build(base, b, image: image), b);
}

/// Develop's spatial analysis (clarity, shadows/highlights, dehaze) of the
/// composite, from the base's analysis proxy: what the GPU graph uses
/// instead of the photo's own aux maps while a backdrop is on.
AuxMaps backdropAuxMaps(BackdropAssets a, BackdropChange b) =>
    AuxMaps.compute(applyBackdrop(a.base.analysisProxy, a, b));
