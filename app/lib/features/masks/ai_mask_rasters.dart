import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';

final _log = Logger('AiMaskRasters');

/// Sorted, de-duplicated `maskRef`s of the AI masks (a stable select key).
String aiMaskRefsKey(List<LocalMask>? masks) {
  final refs = <String>{
    for (final m in masks ?? const <LocalMask>[])
      if (m.kind.isAi && m.ai.maskRef.isNotEmpty) m.ai.maskRef,
  }.toList()..sort();
  return refs.join('\n');
}

/// Decoded rasters of photo [assetId]'s AI masks, by `maskRef`, for the
/// renderer (`MaskRasterSink`). Reloads only when the set of refs changes.
/// A raster that cannot be loaded is left out (that mask covers nothing).
final aiMaskRastersProvider =
    FutureProvider.family<Map<String, MaskRaster>, String>((
      ref,
      assetId,
    ) async {
      final key = ref.watch(
        editorProvider(assetId)
            .select((s) => aiMaskRefsKey(s.value?.settings.masks)),
      );
      final loader = ref.watch(aiMaskRasterLoaderProvider);
      if (key.isEmpty || loader == null) return const {};
      final out = <String, MaskRaster>{};
      for (final maskRef in key.split('\n')) {
        try {
          final raster = await loader.load(assetId, maskRef);
          if (raster != null) out[maskRef] = raster;
        } on Exception catch (e) {
          _log.warning('AI mask $maskRef for $assetId unavailable: $e');
        }
      }
      return Map.unmodifiable(out);
    });
