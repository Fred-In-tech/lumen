import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/import/float_sources.dart';

/// Builds the renderer for an editor session (GPU with CPU fallback).
/// Tests override this with a CPU or fake renderer.
final photoRendererFactoryProvider =
    Provider<PhotoRenderer Function(String assetId)>((ref) {
      final longEdge = ref.watch(previewLongEdgeProvider);
      final floats = ref.watch(floatSourcesProvider);
      return (assetId) => GpuPhotoRenderer(
        assetId: assetId,
        previewLongEdge: longEdge,
        floatSource: floats.open,
      );
    });
