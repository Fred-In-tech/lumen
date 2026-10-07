import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_parser.dart';
import 'package:lumen/ai/ondevice/face_parsing_cache.dart';
import 'package:lumen/ai/ondevice/ondevice_platform.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/features/portrait/retouch_tiles.dart';

final _log = Logger('FaceParsing');

/// The face parser's model: Selfie Multiclass, the model behind AI masks
/// (downloaded on first use, 16.4 MB, Apache-2.0).
const kFaceParserSpec = ModelManifest.selfieMulticlass;

/// Loads a [FaceParser]; with `download: false` only when the model is
/// already on this device (null otherwise).
typedef FaceParserLoader = Future<FaceParser?> Function({bool download});

/// Face parsing of a photo's face tiles, cached per photo. Never throws:
/// every failure (no model, offline, no runtime, a failed run) means "no
/// parsing", and the skin masks fall back to the heuristic.
class FaceParsingService {
  FaceParsingService({required this.cache, required this.parser});

  final Future<FaceParsingCache> Function() cache;
  final FaceParserLoader parser;

  /// The cached parsing of [plans] (same model, same tiles), or null.
  Future<List<FaceParsingPlanes>?> cached(
    String assetId,
    List<FaceTilePlan> plans,
  ) async {
    if (plans.isEmpty) return null;
    try {
      final bytes = await (await cache()).read(assetId);
      if (bytes == null) return null;
      return unwrapParsing(bytes, faceParsingKey(kFaceParserSpec, plans));
    } on Exception catch (e) {
      _log.info('face parsing cache of $assetId unreadable: $e');
      return null;
    }
  }

  /// The parsing of [tiles]: the cache when current, else a model run
  /// (the model is downloaded first when [download] allows it), cached.
  Future<List<FaceParsingPlanes>?> parse(
    String assetId,
    FaceTiles tiles, {
    bool download = true,
  }) async {
    final plans = [for (final t in tiles) t.plan];
    final hit = await cached(assetId, plans);
    if (hit != null || tiles.isEmpty) return hit;
    try {
      final p = await parser(download: download);
      if (p == null) return null;
      final watch = Stopwatch()..start();
      final planes = await p.parse(tiles);
      _log.info(
        'parsed ${planes.length} face tiles of $assetId in '
        '${watch.elapsedMilliseconds} ms',
      );
      try {
        await (await cache()).write(
          assetId,
          wrapParsing(faceParsingKey(kFaceParserSpec, plans), planes),
        );
      } on Exception catch (e) {
        _log.warning('face parsing of $assetId not cached: $e');
      }
      return planes;
    } on Exception catch (e) {
      _log.warning('face parsing unavailable for $assetId: $e');
      return null;
    }
  }
}

final faceParsingCacheProvider = FutureProvider<FaceParsingCache>(
  (ref) => openFaceParsingCache(),
  retry: noRetry,
);

/// The loaded parser (its own session of the AI-mask model).
final faceParserProvider = FutureProvider<FaceParser>((ref) async {
  final store = await ref.watch(modelStoreProvider.future);
  final backend = ref.watch(inferenceBackendProvider);
  final session = await openVerifiedSession(store, backend, kFaceParserSpec);
  final FaceParser parser;
  try {
    parser = FaceParser(session: session, spec: kFaceParserSpec);
  } on Exception {
    await session.dispose();
    rethrow;
  }
  ref.onDispose(() => unawaited(parser.dispose()));
  return parser;
}, retry: noRetry);

final faceParsingServiceProvider = Provider<FaceParsingService>(
  (ref) => FaceParsingService(
    cache: () => ref.read(faceParsingCacheProvider.future),
    parser: ({bool download = true}) async {
      if (ref.read(platformInfoProvider).isWeb) return null;
      if (!download) {
        final store = await ref.read(modelStoreProvider.future);
        if (await store.readyPath(kFaceParserSpec) == null) return null;
      }
      try {
        return await ref.read(faceParserProvider.future);
      } on Exception {
        // Let a later photo retry (e.g. after going back online).
        ref.invalidate(faceParserProvider);
        rethrow;
      }
    },
  ),
);

/// Full-resolution face tiles of a photo (empty when there are no faces or
/// the original cannot be decoded at full size).
final faceTilesProvider = FutureProvider.family<FaceTiles, String>((
  ref,
  assetId,
) async {
  final faces = (await ref.watch(faceAnalysisProvider(assetId).future))
      .analysis;
  if (faces.faces.isEmpty) return const [];
  return loadFaceTiles(ref.watch(catalogRepositoryProvider), assetId, faces);
}, retry: noRetry);

/// The parsing the retouch maps of a photo should use: the cache, else a
/// model run on its face tiles (downloading the model on first use). Never
/// fails (null = heuristic masks); the maps watch it without awaiting, so
/// the first retouch frame never waits for the model.
final faceParsingProvider =
    FutureProvider.family<List<FaceParsingPlanes>?, String>((
      ref,
      assetId,
    ) async {
      final tiles = await ref.watch(faceTilesProvider(assetId).future);
      return ref.read(faceParsingServiceProvider).parse(assetId, tiles);
    }, retry: noRetry);
