import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/import/photo_decoder.dart';

/// Long edge photos are decoded at for on-device analysis (faces, masks):
/// the editor preview size, so coordinates line up with the renderer.
const kOnDeviceAnalysisLongEdge = 2560;

/// A photo decoded for analysis, plus its original (oriented) size.
typedef AnalysisPixels = ({
  RgbaBuffer pixels,
  int sourceWidth,
  int sourceHeight,
});

/// Decodes [assetId]'s original at [longEdge] (UI isolate: engine codec).
Future<AnalysisPixels> loadAnalysisPixels(
  CatalogRepository catalog,
  String assetId, {
  int longEdge = kOnDeviceAnalysisLongEdge,
}) async {
  final entry = await catalog.get(assetId);
  final original = await catalog.readPixelSource(assetId);
  final image = await decodePhoto(original, maxLongEdge: longEdge);
  final RgbaBuffer pixels;
  try {
    pixels = await rgbaFromImage(image);
  } finally {
    image.dispose();
  }
  // Keep the decoded orientation; scale up to the original long edge.
  final srcLong = entry == null ? 0 : math.max(entry.width, entry.height);
  final decLong = math.max(pixels.width, pixels.height);
  final k = srcLong > decLong ? srcLong / decLong : 1.0;
  return (
    pixels: pixels,
    sourceWidth: (pixels.width * k).round(),
    sourceHeight: (pixels.height * k).round(),
  );
}
