import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/import/bit_depth.dart';
import 'package:lumen/import/float_decoder.dart';
import 'package:lumen/import/float_preview_cache.dart';
import 'package:lumen/import/float_preview_store.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('FloatSources');

/// Finds the float source of a catalog photo (docs/HIGH_BIT_DEPTH.md):
/// camera RAW, 16-bit PNG and 10/12-bit HEIC whose original is a file the
/// platform decoder can render in float. Everything else, and every photo
/// on a platform without the decoder, has none and stays on the 8-bit path.
///
/// With a [store], sources keep their editor preview in the float preview
/// cache: reopening a photo reads it back instead of decoding the original
/// (docs/HIGH_BIT_DEPTH.md, "Preview cache").
class FloatSources {
  const FloatSources({
    required this.catalog,
    required this.decoder,
    this.store,
  });

  final CatalogRepository catalog;
  final FloatDecoder decoder;
  final FloatPreviewStore? store;

  /// The original's path when [assetId] is a high-bit-depth photo stored
  /// as a file, else null. Catalogs from before `bitDepth` was recorded:
  /// PNG and HEIC are sniffed from the file header once.
  Future<String?> _candidate(String assetId) async =>
      (await _candidateEntry(assetId))?.path;

  Future<({String path, CatalogEntry entry})?> _candidateEntry(
    String assetId,
  ) async {
    final catalog = this.catalog;
    if (catalog is! OriginalFileLocator) return null;
    final entry = await catalog.get(assetId);
    if (entry == null) return null;
    var depth = entry.bitDepth;
    if (depth == null &&
        (entry.format == PhotoFormat.png.name ||
            entry.format == PhotoFormat.heic.name)) {
      final bytes = await catalog.readOriginal(assetId);
      depth = sniffBitDepth(
        bytes,
        sniffFormat(bytes, fileName: entry.fileName),
      );
    }
    if (!isHighBitDepth(entry.format, depth)) return null;
    final path = await (catalog as OriginalFileLocator).originalFilePath(
      assetId,
    );
    return path == null ? null : (path: path, entry: entry);
  }

  /// The float source of [assetId], or null. Never throws.
  Future<FloatSource?> open(String assetId) async {
    try {
      final path = await _candidate(assetId);
      if (path == null) return null;
      final store = this.store;
      // A cached preview carries the decoder's answer: no native call.
      final info =
          await store?.cache.infoFor(assetId) ?? await decoder.info(path);
      if (info == null) return null;
      final source = DecodedFloatSource(decoder, path, info);
      if (store == null) return source;
      return CachingFloatSource(assetId: assetId, inner: source, store: store);
    } on CatalogException catch (e) {
      _log.info('no float source for $assetId: $e');
      return null;
    }
  }

  /// What the preview store should prepare for [assetIds]: the float
  /// photos among them, at the preview size an editor with
  /// [previewLongEdge] asks for.
  Future<List<FloatPreviewTarget>> targets(
    List<String> assetIds, {
    required int previewLongEdge,
  }) async {
    final out = <FloatPreviewTarget>[];
    for (final id in assetIds) {
      try {
        final c = await _candidateEntry(id);
        if (c == null || c.entry.width <= 0 || c.entry.height <= 0) continue;
        final size = decodedSizeFor(
          c.entry.width,
          c.entry.height,
          previewLongEdge,
        );
        out.add(
          FloatPreviewTarget(
            assetId: id,
            path: c.path,
            width: size.width,
            height: size.height,
          ),
        );
      } on CatalogException catch (e) {
        _log.fine('no float preview target for $id: $e');
      }
    }
    return out;
  }

  /// Loads the previews of [assetIds] (the filmstrip neighbours of the open
  /// photo) into memory in the background, decoding them first when they
  /// are not cached yet. Replaces earlier pending prefetches.
  Future<void> prefetch(
    List<String> assetIds, {
    required int previewLongEdge,
  }) async {
    final store = this.store;
    if (store == null || assetIds.isEmpty) return;
    store.prefetch(await targets(assetIds, previewLongEdge: previewLongEdge));
  }

  /// Builds the missing cache entries of [assetIds] in the background, one
  /// decode at a time at low priority (after an import, in idle time).
  Future<void> warm(
    List<String> assetIds, {
    required int previewLongEdge,
  }) async {
    final store = this.store;
    if (store == null || assetIds.isEmpty) return;
    store.warm(await targets(assetIds, previewLongEdge: previewLongEdge));
  }
}

final floatDecoderProvider = Provider<FloatDecoder>(
  (ref) => const PlatformFloatDecoder(),
);

/// Long edge of the editor preview on this device (the float preview size
/// the cache and the prefetch prepare).
final previewLongEdgeProvider = Provider<int>(
  (ref) => ref.watch(platformInfoProvider).isMobile ? 2048 : 2560,
);

/// The float preview cache folder (none on the web and off Apple).
final floatPreviewCacheProvider = Provider<FloatPreviewCache>(
  (ref) => platformFloatPreviewCache(platform: ref.watch(platformInfoProvider)),
);

/// Float previews in memory and on disk, shared by all editor sessions.
final floatPreviewStoreProvider = Provider<FloatPreviewStore>((ref) {
  final store = FloatPreviewStore(
    decoder: ref.watch(floatDecoderProvider),
    cache: ref.watch(floatPreviewCacheProvider),
  );
  ref.onDispose(store.dispose);
  return store;
});

final floatSourcesProvider = Provider<FloatSources>(
  (ref) => FloatSources(
    catalog: ref.watch(catalogRepositoryProvider),
    decoder: ref.watch(floatDecoderProvider),
    store: ref.watch(floatPreviewStoreProvider),
  ),
);

/// True when [assetId] is edited on the float path on this device: it has a
/// float source and the renderer passed the float probe. The info panel
/// shows it ("Editing: 32-bit float").
final floatEditingProvider = FutureProvider.family<bool, String>((
  ref,
  assetId,
) async {
  final source = await ref.watch(floatSourcesProvider).open(assetId);
  return source != null && await HbdCapability.available();
});
