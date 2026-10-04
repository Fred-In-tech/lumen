import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/data/patch_store_platform.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/remove/ai_remover.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen/platform/cancellable_task.dart';

/// Heal patch PNGs next to the catalog (memory on web; override in tests).
final patchStoreProvider = FutureProvider<PatchStore>(
  (ref) => openPatchStore(),
);

/// The on-device inpainting model (MI-GAN) when the user has AI fill on
/// and it is loaded; null otherwise (removal then uses the classic engines).
final removeModelProvider = Provider<InpaintModel?>((ref) {
  final ai = ref.watch(aiRemoverProvider);
  return ai.usable ? ai.model : null;
});

/// Full-resolution, upright pixels of a photo.
typedef SourceLoader = Future<RgbaBuffer> Function(String assetId);

/// Decodes the original at full size with the same codec as the editor, so
/// normalized strokes land on the same pixels.
Future<RgbaBuffer> loadFullResSource(
  CatalogRepository catalog,
  String assetId,
) async {
  final bytes = await catalog.readOriginal(assetId);
  final image = await decodePhoto(bytes);
  try {
    return await rgbaFromImage(image);
  } finally {
    image.dispose();
  }
}

final removeSourceLoaderProvider = Provider<SourceLoader>((ref) {
  final catalog = ref.watch(catalogRepositoryProvider);
  return (assetId) => loadFullResSource(catalog, assetId);
});

/// Starts cancellable background work (an isolate per task on native).
final cancellableRunnerProvider = Provider<CancellableRunner>(
  (ref) => runCancellable,
);
