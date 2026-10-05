import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/import/bit_depth.dart';
import 'package:lumen/import/float_decoder.dart';
import 'package:lumen/import/import_file.dart';

final _log = Logger('FloatSources');

/// Finds the float source of a catalog photo (docs/HIGH_BIT_DEPTH.md):
/// camera RAW, 16-bit PNG and 10/12-bit HEIC whose original is a file the
/// platform decoder can render in float. Everything else, and every photo
/// on a platform without the decoder, has none and stays on the 8-bit path.
class FloatSources {
  const FloatSources({required this.catalog, required this.decoder});

  final CatalogRepository catalog;
  final FloatDecoder decoder;

  /// The original's path when [assetId] is a high-bit-depth photo stored
  /// as a file, else null. Catalogs from before `bitDepth` was recorded:
  /// PNG and HEIC are sniffed from the file header once.
  Future<String?> _candidate(String assetId) async {
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
    return (catalog as OriginalFileLocator).originalFilePath(assetId);
  }

  /// The float source of [assetId], or null. Never throws.
  Future<FloatSource?> open(String assetId) async {
    try {
      final path = await _candidate(assetId);
      if (path == null) return null;
      final info = await decoder.info(path);
      if (info == null) return null;
      return DecodedFloatSource(decoder, path, info);
    } on CatalogException catch (e) {
      _log.info('no float source for $assetId: $e');
      return null;
    }
  }
}

final floatDecoderProvider = Provider<FloatDecoder>(
  (ref) => const PlatformFloatDecoder(),
);

final floatSourcesProvider = Provider<FloatSources>(
  (ref) => FloatSources(
    catalog: ref.watch(catalogRepositoryProvider),
    decoder: ref.watch(floatDecoderProvider),
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
