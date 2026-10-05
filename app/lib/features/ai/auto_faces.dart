import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/ondevice_providers.dart';

final _log = Logger('AutoFaces');

/// Loads the face boxes Auto Enhance anchors exposure and white balance on.
typedef FaceBoxLoader = Future<List<FaceBox>> Function(String assetId);

/// Face boxes of [assetId] from the local face cache (analysed on first
/// use). Never throws: where face analysis cannot run (web, missing
/// models) Auto Enhance simply works from the whole frame.
///
/// Only the boxes are handed on, and only for the duration of the solve:
/// face geometry stays in the local cache, never in the edit document.
final autoEnhanceFacesProvider = Provider<FaceBoxLoader>(
  (ref) => (assetId) async {
    try {
      final entry = await ref.read(faceAnalysisProvider(assetId).future);
      return [for (final f in entry.analysis.faces) f.box];
    } on Object catch (e) {
      _log.fine('no faces for auto enhance of $assetId: $e');
      return const [];
    }
  },
);
