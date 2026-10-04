import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/patch_store.dart';

/// [count] fresh op ids whose refs (`retouch/<id>.png`) none of [takenRefs]
/// use, so a new PNG never overwrites one an undo could bring back.
List<String> newHealOpIds(Set<String> takenRefs, int count) {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final ids = <String>[];
  for (var n = 0; ids.length < count; n++) {
    final id = 'h${stamp}_$n';
    if (!takenRefs.contains('$kRetouchDir/$id.png')) ids.add(id);
  }
  return ids;
}

/// Heal ops moved to another photo, and how many could not be.
class HealTransfer {
  const HealTransfer(this.ops, this.skipped);

  final List<HealOp> ops;

  /// Ops dropped because their patch PNG is missing in the source photo.
  final int skipped;
}

/// Copies [ops]' patch PNGs from [fromAsset] into [toAsset] under fresh ids
/// (avoiding [takenRefs]) and rewrites the ops to point at the copies.
/// Ops whose patch is missing are skipped and counted.
Future<HealTransfer> transferHealOps(
  PatchStore store, {
  required String fromAsset,
  required String toAsset,
  required List<HealOp> ops,
  Set<String> takenRefs = const {},
}) async {
  if (fromAsset == toAsset || ops.isEmpty) return HealTransfer(ops, 0);
  final ids = newHealOpIds(takenRefs, ops.length);
  final out = <HealOp>[];
  var skipped = 0;
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final ref = '$kRetouchDir/${ids[i]}.png';
    final copied =
        op.isRenderable && await store.copy(fromAsset, op.patch, toAsset, ref);
    if (copied) {
      out.add(_rebased(op, ids[i], ref));
    } else {
      skipped++;
    }
  }
  return HealTransfer(List.unmodifiable(out), skipped);
}

HealOp _rebased(HealOp op, String id, String patch) => HealOp(
  id: id,
  kind: op.kind,
  engine: op.engine,
  ai: op.ai,
  strokes: op.strokes,
  bbox: op.bbox,
  srcWidth: op.srcWidth,
  srcHeight: op.srcHeight,
  patch: patch,
  cloneOffset: op.cloneOffset,
  hidden: op.hidden,
  createdAt: op.createdAt,
  faceIntersect: op.faceIntersect,
);

/// [source] made ready to paste onto [targetAssetId]. When [groups] carry
/// heal ops or a background-swap image from another photo, their PNGs are
/// copied into the target under fresh names first (the paste itself stays
/// one history entry). Items whose PNG cannot be found (or without a
/// [sourceAssetId]) are dropped and counted in `skipped`.
Future<({DevelopSettings settings, int skipped})> prepareHealPaste({
  required DevelopSettings source,
  required Set<SettingsGroup> groups,
  required String? sourceAssetId,
  required String targetAssetId,
  required EditDocument targetDoc,
  required PatchStoreGetter store,
}) async {
  if (sourceAssetId == targetAssetId) return (settings: source, skipped: 0);
  final taken = referencedPatchRefs(targetDoc);
  var settings = source;
  var skipped = 0;
  if (groups.contains(SettingsGroup.heal) && source.heal.isNotEmpty) {
    if (sourceAssetId == null) {
      settings = settings.copyWith(heal: const []);
      skipped += source.heal.length;
    } else {
      final moved = await transferHealOps(
        await store(),
        fromAsset: sourceAssetId,
        toAsset: targetAssetId,
        ops: source.heal,
        takenRefs: taken,
      );
      settings = settings.copyWith(heal: moved.ops);
      skipped += moved.skipped;
      taken.addAll(moved.ops.map((o) => o.patch));
    }
  }
  final image = source.backdrop.imageRef;
  if (groups.contains(SettingsGroup.backdrop) && image.isNotEmpty) {
    final ref = '$kRetouchDir/bg${newHealOpIds(taken, 1).single}.png';
    final copied =
        sourceAssetId != null &&
        await (await store()).copy(sourceAssetId, image, targetAssetId, ref);
    settings = settings.copyWith(
      backdrop: settings.backdrop.copyWith(imageRef: copied ? ref : ''),
    );
    if (!copied) skipped++;
  }
  return (settings: settings, skipped: skipped);
}
