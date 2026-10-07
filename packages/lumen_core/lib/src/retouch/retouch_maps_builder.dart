/// Builds [RetouchMaps] once per photo (research 07 §3.0, §6.3).
///
/// [computeRetouchMaps] is a pure top-level function on plain data, so it
/// can run in `Isolate.run` unchanged.
library;

import 'dart:typed_data';

import '../model/face_analysis.dart';
import '../model/mask_shapes.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_build.dart';
import 'backdrop_maps.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_ids.dart';
import 'face_maps.dart';
import 'face_mesh.dart';
import 'face_parsing_input.dart';
import 'face_tiles.dart';
import 'kernel_constants.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'retouch_maps.dart';
import 'skin_pen.dart';
import 'wrinkle_map.dart';

/// Computes the retouch maps of [source] (an analysis decode of the
/// photo) for the first [kMaxRetouchFaces] faces of [analysis].
///
/// Each face is analysed on its own tile (`face_tiles.dart`): [tiles]
/// supplies tile pixels by slot (e.g. crops of the full-resolution
/// original, planned with [planFaceTiles] on the original's size); faces
/// without one get a tile resampled from [source]. The finished tiles are
/// packed into one atlas, each face with its source-uv → map transform.
/// Faces below [kMinFaceIodSourcePx] of IOD in [source] are skipped.
///
/// [parsing] planes are matched by face id. With [backdrop] (person /
/// hair rasters) the image-scope backdrop maps are built too, even when
/// the photo has no faces. [skinPen] (Manual Tuning Pen strokes) is
/// applied last, exactly like `applySkinPen` on the pen-free maps.
RetouchMaps computeRetouchMaps(
  RgbaBuffer source,
  FaceAnalysis analysis, {
  List<FaceParsingPlanes>? parsing,
  List<FaceTileImage> tiles = const [],
  double targetIod = kTileTargetIod,
  int budgetPx = kTileBudgetPx,
  BlemishOverrides overrides = BlemishOverrides.none,
  BackdropInput? backdrop,
  List<BrushStroke> skinPen = const [],
}) {
  final inputs = retouchTileInputs(
    source,
    analysis,
    tiles: tiles,
    targetIod: targetIod,
    budgetPx: budgetPx,
  );
  return assembleRetouchMaps(
    [
      for (final t in inputs)
        computeFaceTileMaps(
          analysis,
          t,
          parsing: parsing,
          overrides: overrides,
        ),
    ].whereType<FaceTileMaps>().toList(),
    backdrop: computeBackdropMaps(source, backdrop),
    skinPen: skinPen,
  );
}

/// The tile of every retouchable face (slot order): the matching one of
/// [tiles], else one resampled from [source]. Faces below
/// [kMinFaceIodSourcePx] of IOD in [source] get none. The first step of
/// [computeRetouchMaps], split out so faces can be built in parallel.
List<FaceTileImage> retouchTileInputs(
  RgbaBuffer source,
  FaceAnalysis analysis, {
  List<FaceTileImage> tiles = const [],
  double targetIod = kTileTargetIod,
  int budgetPx = kTileBudgetPx,
}) {
  final given = <int, FaceTileImage>{
    for (final t in tiles)
      if (t.plan.slot < analysis.faces.length &&
          analysis.faces[t.plan.slot].id == t.plan.faceId)
        t.plan.slot: t,
  };
  final inputs = <FaceTileImage>[];
  for (final plan in planFaceTiles(
    analysis,
    source.width,
    source.height,
    targetIod: targetIod,
    budgetPx: budgetPx,
  )) {
    final gate = FaceFrame.tryCreate(
      analysis.faces[plan.slot],
      plan.slot,
      source.width,
      source.height,
      minIod: kMinFaceIodSourcePx,
    );
    if (gate == null) continue;
    inputs.add(
      given[plan.slot] ?? FaceTileImage(plan, resampleTile(source, plan)),
    );
  }
  return inputs;
}

/// One face's finished planes and the tile they were built on.
typedef FaceTileMaps = ({FaceTilePlan plan, FaceMapPlanes planes});

/// The planes of the face of [tile] (null when it has no usable mesh).
/// Pure and isolate-safe: faces can be built in parallel. [parsing] is
/// searched for this face's planes.
FaceTileMaps? computeFaceTileMaps(
  FaceAnalysis analysis,
  FaceTileImage tile, {
  List<FaceParsingPlanes>? parsing,
  BlemishOverrides overrides = BlemishOverrides.none,
}) {
  final p = tile.plan;
  final face = analysis.faces[p.slot];
  final faceParsing = parsing?.where((q) => q.faceId == face.id).firstOrNull;
  // Without parsing the work rect is today's (the tile's neck reach is
  // only for skin the parser finds there).
  final f = FaceFrame.tryCreate(
    face,
    p.slot,
    p.gridW,
    p.gridH,
    window: p.window,
    fillWindow: faceParsing != null,
  );
  if (f == null || f.rect.isEmpty) return null;
  return (
    plan: p,
    planes: computeFaceMaps(
      f,
      tile.pixels,
      originX: p.window.x0,
      originY: p.window.y0,
      gridW: p.gridW,
      gridH: p.gridH,
      parsing: faceParsing,
      overrides: overrides,
    ),
  );
}

/// Packs finished faces into the atlas [RetouchMaps] (the last step of
/// [computeRetouchMaps]), with [backdrop] maps and the [skinPen] applied.
RetouchMaps assembleRetouchMaps(
  List<FaceTileMaps> faces, {
  BackdropMaps? backdrop,
  List<BrushStroke> skinPen = const [],
}) {
  final bd = backdrop ?? BackdropMaps.none(BackdropState.notRequested);
  if (faces.isEmpty) return RetouchMaps.empty(backdrop: bd);
  return applySkinPen(
    _assemble([for (final f in faces) (f.plan, f.planes)], bd),
    skinPen,
  );
}

RetouchMaps _assemble(
  List<(FaceTilePlan, FaceMapPlanes)> built,
  BackdropMaps backdrop,
) {
  final atlas = packAtlas([
    for (final (_, q) in built) (w: q.frame.rect.w, h: q.frame.rect.h),
  ]);
  final w = atlas.width, h = atlas.height, n = w * h * 4;
  final low = Uint8List(n);
  for (var i = 3; i < n; i += 4) {
    low[i] = 255;
  }
  Uint8List tex(int fill) {
    final t = Uint8List(2 * n);
    if (fill != 0) t.fillRange(0, 2 * n, fill);
    for (var i = 3; i < 2 * n; i += 4) {
      t[i] = 255;
    }
    return t;
  }

  final da = tex(128), db = tex(128), dc = tex(128);
  final ra = tex(0), rb = tex(0);
  final rects = [
    for (var k = 0; k < built.length; k++)
      MapRect(
        atlas.origins[k].x,
        atlas.origins[k].y,
        built[k].$2.frame.rect.w,
        built[k].$2.frame.rect.h,
      ),
  ];
  final faces = [
    for (var k = 0; k < built.length; k++)
      _info(built[k].$2, built[k].$1, rects[k]),
  ];
  final owner = faceOwners(faces, w, h);
  for (var k = 0; k < built.length; k++) {
    final p = built[k].$2, slot = p.frame.slot;
    LabPlanes(
      rects[k],
      p.low.l,
      p.low.a,
      p.low.b,
    ).writeSrgb(low, w, owner, slot, seed: kDitherSeedLow);
    _writeFace(p, rects[k], w, owner, da, db, dc, ra, rb);
    assignFaceIds(faces[k], w, owner, db, ra, rb);
  }
  return RetouchMaps(
    width: w,
    height: h,
    low: low,
    deltaA: da,
    deltaB: db,
    deltaC: dc,
    regionA: ra,
    regionB: rb,
    faces: faces,
    backdrop: backdrop,
    blemishes: List.unmodifiable([for (final (_, p) in built) ...p.blemishes]),
  );
}

/// The face info of [p] placed at [at] in the atlas: every map-pixel
/// position moves by the tile offset.
RetouchFaceInfo _info(FaceMapPlanes p, FaceTilePlan plan, MapRect at) {
  final f = p.frame, model = p.regions.skinModel;
  final dx = (at.x0 - f.rect.x0).toDouble();
  final dy = (at.y0 - f.rect.y0).toDouble();
  return RetouchFaceInfo(
    slot: f.slot,
    faceId: f.faceId,
    rect: at,
    mapScaleX: plan.gridW.toDouble(),
    mapScaleY: plan.gridH.toDouble(),
    mapOffsetX: dx,
    mapOffsetY: dy,
    iod: f.iod,
    teethCapL: p.regions.teethCapL,
    skinMeanL: model.meanL,
    lipGlossL: p.regions.makeup.glossL,
    lipChromaGain: p.regions.makeup.lipChromaGain,
    lipShiftL: p.regions.makeup.lipShiftL,
    blushA: kBlushChroma * (p.regions.makeup.blushA - model.meanA),
    blushB: kBlushChroma * (p.regions.makeup.blushB - model.meanB),
    hasForcedSpots: p.hasForcedSpots,
    eyeRightX: f.xs[FaceMesh.rightIrisCenter] + dx,
    eyeRightY: f.ys[FaceMesh.rightIrisCenter] + dy,
    eyeLeftX: f.xs[FaceMesh.leftIrisCenter] + dx,
    eyeLeftY: f.ys[FaceMesh.leftIrisCenter] + dy,
    // FaceFrame.ownershipDistance: the nose, 0.45 IOD below the eyes.
    centerX: f.eyeMid.x + kOwnershipCenterIod * f.iod * f.axis.x + dx,
    centerY: f.eyeMid.y + kOwnershipCenterIod * f.iod * f.axis.y + dy,
    skin: p.deltas.measure,
  );
}

/// 0..1 → byte without `num.clamp` (hot loop).
int _byte(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255 + 0.5).toInt());

/// Writes the planes of [p] into the atlases at [rect] (its tile).
void _writeFace(
  FaceMapPlanes p,
  MapRect rect,
  int w,
  Int8List owner,
  Uint8List da,
  Uint8List db,
  Uint8List dc,
  Uint8List ra,
  Uint8List rb,
) {
  final r = p.regions, heal = p.heal, d = p.deltas;
  final wr = p.wrinkles, slot = p.frame.slot;
  const sm = RetouchDelta.smooth, sh = RetouchDelta.shine;
  const hl = RetouchDelta.heal, dk = RetouchDelta.darkCircles;
  const be = RetouchDelta.bagEven, ey = RetouchDelta.eyes;
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (owner[y * w + x] != slot) continue;
      final left = (y * 2 * w + x) * 4, right = left + w * 4;
      double dith(int c, int t) => ditherAt(x, y, kDitherSeedDelta + t, c);
      void put(
        Uint8List t,
        int o,
        int k,
        RetouchDelta rd,
        double a,
        double b,
        double c,
      ) {
        t[o] = encodeSignedDithered(a, rd.r0, dith(0, k));
        t[o + 1] = encodeSignedDithered(b, rd.r1, dith(1, k));
        t[o + 2] = encodeSignedDithered(c, rd.r2, dith(2, k));
      }

      put(da, left, 0, sm, d.smooth.l[i], d.smooth.a[i], d.smooth.b[i]);
      put(da, right, 1, sh, d.shine.l[i], d.shine.a[i], d.shine.b[i]);
      put(db, left, 2, hl, heal.dl[i], heal.da[i], heal.db[i]);
      put(
        db,
        right,
        3,
        dk,
        d.darkCircle.l[i],
        d.darkCircle.a[i],
        d.darkCircle.b[i],
      );
      put(dc, left, 4, be, d.bag[i], d.evenA[i], d.evenB[i]);
      dc[right] = encodeSigned(p.irisL[i], ey.r0);
      dc[right + 1] = encodeSigned(p.veinA[i], ey.r1);
      dc[right + 2] = encodeSigned(p.veinL[i], ey.r2);
      final wrinkle = encodeWrinkle(wr.delta[i]);
      ra[left] = _byte(r.skin[i]);
      ra[left + 1] = _byte(r.underEye[i]);
      ra[left + 2] = _byte(r.lash[i]);
      ra[right] = _byte(r.mouth[i]);
      ra[right + 1] = _byte(r.sclera[i]);
      ra[right + 2] = _byte(r.iris[i]);
      rb[left] = _byte(r.lips[i]);
      rb[left + 1] = _byte(r.blush[i]);
      rb[left + 2] = wrinkle;
      rb[right + 1] = heal.spotCode[i];
      rb[right + 2] = wrinkle == 0 ? 0 : wr.zone[i];
    }
  }
}

// Face ids: face_ids.dart (shared with the Manual Tuning Pen).
