import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/platform/background.dart';

/// Per-photo inputs of a source render beyond the settings: AI mask
/// rasters, portrait retouch maps with the analysis they came from, and
/// the asset id (it seeds the grain, as in the editor).
typedef SourceInputs = ({
  String assetId,
  Map<String, MaskRaster> maskRasters,
  RetouchMaps? retouchMaps,
  FaceAnalysis? faces,
  BackdropInputs backdrop,
});

/// Loads a photo's background-swap inputs (person/hair rasters and the
/// backdrop image) for [change]; [kNoBackdropInputs] when it is off.
typedef BackdropInputsLoader = Future<BackdropInputs> Function(
  String assetId,
  BackdropChange change,
);

/// Develops decoded source pixels (already healed) for export, in the
/// order heal → portrait retouch → develop (masks included).
abstract interface class SourceRenderer {
  /// The long edge to decode the original at for an export of [longEdge]
  /// (null = full size).
  int? decodeLongEdge(int? longEdge);

  /// Renders [source] with [settings]; the output long edge is [longEdge]
  /// at most (null: the source size, after crop).
  Future<RgbaBuffer> render(
    RgbaBuffer source,
    DevelopSettings settings,
    SourceInputs inputs, {
    int? longEdge,
  });
}

/// The CPU reference: decodes at the export size, retouches and develops in
/// a background isolate. Correct everywhere.
class CpuSourceRenderer implements SourceRenderer {
  const CpuSourceRenderer();

  @override
  int? decodeLongEdge(int? longEdge) => longEdge;

  @override
  Future<RgbaBuffer> render(
    RgbaBuffer source,
    DevelopSettings settings,
    SourceInputs inputs, {
    int? longEdge,
  }) async {
    final src = await downscaleTo(source, longEdge);
    return developInBackground(
      src,
      settings,
      inputs.maskRasters,
      inputs.retouchMaps,
      inputs.faces,
      backdrop: inputs.backdrop,
    );
  }
}

/// [src] with its long edge at most [longEdge] (the same buffer when it
/// already fits).
Future<RgbaBuffer> downscaleTo(RgbaBuffer src, int? longEdge) async {
  final le = src.width > src.height ? src.width : src.height;
  if (longEdge == null || longEdge >= le) return src;
  final img = await imageFromRgba(src);
  try {
    final small = await resizeImage(img, longEdge);
    try {
      return await rgbaFromImage(small);
    } finally {
      small.dispose();
    }
  } finally {
    img.dispose();
  }
}

/// Portrait retouch, then the reference develop, off the UI isolate.
/// Top-level so the isolate closure captures only its arguments.
Future<RgbaBuffer> developInBackground(
  RgbaBuffer src,
  DevelopSettings settings,
  Map<String, MaskRaster> rasters,
  RetouchMaps? maps,
  FaceAnalysis? faces, {
  BackdropInputs backdrop = kNoBackdropInputs,
}) async {
  final lut = await CreativeLuts.forSettings(settings);
  return runInBackground(
    () => renderReference(
      backdroppedSource(
        retouchedSource(src, settings, maps, faces),
        settings.backdrop,
        people: backdrop.people,
        hair: backdrop.hair,
        image: backdrop.image,
      ),
      settings,
      maskRasters: rasters,
      faces: faces,
      creativeLut: lut,
    ),
  );
}
