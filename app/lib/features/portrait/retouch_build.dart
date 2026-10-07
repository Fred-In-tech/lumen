import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_parsing.dart';
import 'package:lumen/features/portrait/retouch_tiles.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('RetouchBuild');

/// Builds the retouch maps off the UI isolate. Top-level so the isolate
/// closure only captures plain data. [tiles] are full-resolution face
/// crops (`retouch_tiles.dart`; faces without one use the decode),
/// [parsing] the per-face segmentation (null: heuristic skin masks).
/// [backdrop] (person / hair / clothes rasters) adds the image-scope
/// backdrop and clothing maps; [skinPen] applies the Manual Tuning Pen
/// (the editor applies it separately with `applySkinPen`, so pen strokes
/// never re-run this).
Future<RetouchMaps> computeRetouchMapsInBackground(
  RgbaBuffer pixels,
  FaceAnalysis faces,
  PortraitSpots spots, {
  List<FaceTileImage> tiles = const [],
  List<FaceParsingPlanes>? parsing,
  BackdropInput? backdrop,
  List<BrushStroke> skinPen = const [],
}) async {
  final overrides = BlemishOverrides(
    keepAt: spots.keep,
    removeAt: spots.remove,
  );
  // Each face is built in its own isolate (faces are independent), the
  // backdrop next to them; the atlas is packed in one more.
  final inputs = faces.faces.isEmpty
      ? const <FaceTileImage>[]
      : await runInBackground(
          () => retouchTileInputs(pixels, faces, tiles: tiles),
        );
  final built = Future.wait([
    for (final t in inputs)
      runInBackground(
        () => computeFaceTileMaps(
          faces,
          t,
          parsing: parsing,
          overrides: overrides,
        ),
      ),
  ]);
  final bd = backdrop == null
      ? null
      : runInBackground(() => computeBackdropMaps(pixels, backdrop));
  final done = (await built).whereType<FaceTileMaps>().toList();
  final backdropMaps = await bd;
  return runInBackground(
    () => assembleRetouchMaps(done, backdrop: backdropMaps, skinPen: skinPen),
  );
}

/// [tiles] without the faces a visible heal op of [heal] touches: those
/// faces are analysed on the healed decode (where the heal is drawn).
List<FaceTileImage> tilesWithoutHeals(
  List<FaceTileImage> tiles,
  List<HealOp> heal,
  FaceAnalysis faces,
) {
  if (tiles.isEmpty) return tiles;
  final healed = facesWithHeals(heal, faces);
  if (healed.isEmpty) return tiles;
  return [
    for (final t in tiles)
      if (!healed.contains(t.plan.faceId)) t,
  ];
}

/// Which image-scope rasters a photo's edits need.
typedef ImageRasterRequest = ({bool backdrop, bool clothes});

/// The image-scope rasters [settings] need (backdrop: person / hair;
/// clothing: clothes), or null when no image-scope value is set.
ImageRasterRequest? imageRasterRequest(PortraitSettings settings) {
  final backdrop = needsBackdropMaps(settings);
  final clothes = needsClothesMaps(settings);
  return backdrop || clothes ? (backdrop: backdrop, clothes: clothes) : null;
}

/// Loads the rasters the image-scope maps need through the AI mask
/// pipeline (segments the photo once if needed; read-only use): person and
/// hair for the backdrop, clothes for the clothing cleanup, each only when
/// [want] asks for it. A raster that is unavailable (web, no model,
/// offline, failure) stays null, so the maps carry why its sliders do
/// nothing; with nothing available for a backdrop-only request the result
/// is [BackdropInput.missing].
Future<BackdropInput> loadBackdropRasters(
  AiMaskSource? source,
  AiMaskRasterLoader? loader,
  String assetId, {
  ImageRasterRequest want = (backdrop: true, clothes: false),
}) async {
  Future<MaskRaster?> raster(MaskKind kind) async {
    if (source == null || loader == null || !source.supports(kind)) {
      return null;
    }
    try {
      return await loader.load(
        assetId,
        (await source.segment(assetId, kind)).maskRef,
      );
    } on Exception catch (e) {
      _log.warning('${kind.name} mask unavailable for $assetId: $e');
      return null;
    }
  }

  final people = want.backdrop ? await raster(MaskKind.person) : null;
  final hair = people != null ? await raster(MaskKind.hair) : null;
  final clothes = want.clothes ? await raster(MaskKind.clothes) : null;
  if (people == null && clothes == null) return _unavailable(want);
  return BackdropInput(
    people: people,
    hair: hair,
    clothes: clothes,
    wantsBackdrop: want.backdrop,
    wantsClothes: want.clothes,
  );
}

/// Loads the image-scope rasters of a photo (see [loadBackdropRasters]).
typedef BackdropRasterLoader = Future<BackdropInput> Function(
  String assetId,
  ImageRasterRequest want,
);

/// How far around a detected face box a heal still counts as "on the face"
/// (the retouch maps reach the hairline and the jaw).
const kFaceHealMargin = 0.2;

/// The visible heal ops whose box overlaps a face box (grown by
/// [kFaceHealMargin] of its size): those change what the retouch analysis
/// should see.
List<HealOp> healOpsOnFaces(List<HealOp> ops, FaceAnalysis faces) {
  if (ops.isEmpty || faces.faces.isEmpty) return const [];
  return [
    for (final op in ops)
      if (!op.hidden && op.isRenderable && _onAFace(op, faces)) op,
  ];
}

bool _onAFace(HealOp op, FaceAnalysis faces) {
  final x0 = op.bbox.x / op.srcWidth, y0 = op.bbox.y / op.srcHeight;
  final x1 = op.bbox.right / op.srcWidth, y1 = op.bbox.bottom / op.srcHeight;
  for (final f in faces.faces) {
    final b = f.box;
    final mx = b.width * kFaceHealMargin, my = b.height * kFaceHealMargin;
    if (math.max(x0, b.x - mx) < math.min(x1, b.x + b.width + mx) &&
        math.max(y0, b.y - my) < math.min(y1, b.y + b.height + my)) {
      return true;
    }
  }
  return false;
}

/// A stable key of [healOpsOnFaces] (op ids): the retouch maps are rebuilt
/// only when it changes, never for heals away from the faces.
String faceHealKey(List<HealOp>? ops, FaceAnalysis? faces) => faces == null
    ? ''
    : healOpsOnFaces(ops ?? const [], faces).map((o) => o.id).join(',');

/// [pixels] (an analysis decode, any size) with the heal ops that touch a
/// face drawn in, so blemish and skin analysis sees the healed face.
Future<RgbaBuffer> healedAnalysisPixels(
  RgbaBuffer pixels, {
  required String assetId,
  required List<HealOp> ops,
  required FaceAnalysis faces,
  required PatchStoreGetter? patches,
}) async {
  final onFaces = healOpsOnFaces(ops, faces);
  if (patches == null || onFaces.isEmpty) return pixels;
  return composeHealedFullRes(await patches(), assetId, pixels, onFaces);
}

/// Portrait retouch inputs for a stored photo, or why there are none.
typedef StoredRetouch = ({
  RetouchMaps? maps,
  FaceAnalysis? faces,
  String? note,
});

const StoredRetouch kNoRetouch = (maps: null, faces: null, note: null);

final Future<StoredRetouch> kNoRetouchFuture = Future.value(kNoRetouch);

/// Loads a stored photo's retouch inputs ([StoredRetouchLoader.load]).
typedef RetouchLoader = Future<StoredRetouch> Function(
  String assetId,
  DevelopSettings settings,
);

/// Shown with an export or thumbnail that had to skip portrait retouch.
const kRetouchSkippedNote =
    'Portrait retouch was skipped: face analysis is unavailable here.';

/// Loads what export, batch and thumbnails need to apply portrait retouch
/// to a photo that may never have been opened: the face analysis (cached,
/// else run now and cached) and the retouch maps (built in the background,
/// from the healed analysis pixels when heals touch a face).
class StoredRetouchLoader {
  StoredRetouchLoader({
    required this.catalog,
    required this.faceService,
    this.patches,
    this.backdrop,
    this.parsing,
  });

  final CatalogRepository catalog;

  /// Face parsing (cached, or run when the model is already on the
  /// device: export never starts a model download). Null: heuristic masks.
  final FaceParsingService? parsing;
  final Future<FaceAnalysisService> Function() faceService;
  final PatchStoreGetter? patches;

  /// Person / hair / clothes rasters for image-scope edits (null: none
  /// available).
  final BackdropRasterLoader? backdrop;

  /// Never throws: when analysis cannot run (web, missing models) the
  /// result has no maps and a [kRetouchSkippedNote].
  Future<StoredRetouch> load(String assetId, DevelopSettings settings) async {
    if (!portraitNeedsRetouch(settings.portrait)) return kNoRetouch;
    final want = imageRasterRequest(settings.portrait);
    try {
      final service = await faceService();
      var entry = await service.cached(assetId);
      AnalysisPixels? decoded;
      if (entry == null) {
        final d = decoded = await loadAnalysisPixels(catalog, assetId);
        entry = await service.analyze(
          assetId,
          pixels: () async => d.pixels,
          sourceWidth: d.sourceWidth,
          sourceHeight: d.sourceHeight,
        );
      }
      final faces = entry.analysis;
      if (faces.faces.isEmpty && want == null) return kNoRetouch;
      decoded ??= await loadAnalysisPixels(catalog, assetId);
      final pixels = await healedAnalysisPixels(
        decoded.pixels,
        assetId: assetId,
        ops: settings.heal,
        faces: faces,
        patches: patches,
      );
      final tiles = await loadFaceTiles(catalog, assetId, faces);
      final parsed = await parsing?.parse(assetId, tiles, download: false);
      final maps = await computeRetouchMapsInBackground(
        pixels,
        faces,
        settings.portrait.spots,
        tiles: tilesWithoutHeals(tiles, settings.heal, faces),
        parsing: parsed,
        skinPen: settings.portrait.skinPen,
        backdrop: want == null
            ? null
            : await (backdrop?.call(assetId, want) ??
                  Future.value(_unavailable(want))),
      );
      return maps.isUsable
          ? (maps: maps, faces: faces, note: null)
          : kNoRetouch;
    } on Exception catch (e) {
      _log.warning('portrait retouch skipped for $assetId: $e');
      return (maps: null, faces: null, note: kRetouchSkippedNote);
    }
  }
}

/// [want] with no raster available.
BackdropInput _unavailable(ImageRasterRequest want) =>
    want.backdrop && !want.clothes
    ? BackdropInput.missing
    : BackdropInput(wantsBackdrop: want.backdrop, wantsClothes: want.clothes);

final storedRetouchLoaderProvider = Provider<StoredRetouchLoader>(
  (ref) => StoredRetouchLoader(
    catalog: ref.watch(catalogRepositoryProvider),
    faceService: () => ref.read(faceAnalysisServiceProvider.future),
    patches: () => ref.read(patchStoreProvider.future),
    parsing: ref.watch(faceParsingServiceProvider),
    backdrop: (id, want) => loadBackdropRasters(
      ref.read(aiMaskSourceProvider),
      ref.read(aiMaskRasterLoaderProvider),
      id,
      want: want,
    ),
  ),
);
