import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/platform/background.dart';

/// Folder under `assets/<id>/` that holds heal / remove / clone patch PNGs.
///
/// Unlike `cache/` (rebuildable, device-local, never exported), `retouch/`
/// is part of the edit: anything that moves an edit to another place
/// (sync, backup, an edit bundle) must carry `assets/<id>/retouch/` with
/// `edit.json`, or the ops render as nothing.
const kRetouchDir = 'retouch';

final _assetIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final _patchRefPattern = RegExp(r'^retouch/[A-Za-z0-9_-]{1,128}\.png$');

/// Returns [assetId] when it cannot escape the asset folder; throws otherwise.
String checkPatchAssetId(String assetId) {
  if (!_assetIdPattern.hasMatch(assetId)) {
    throw ArgumentError.value(assetId, 'assetId', 'not a valid asset id');
  }
  return assetId;
}

/// True for a ref the store reads and writes: `retouch/<name>.png`, and
/// unchanged by [sanitizePatchRef] (no `..`, absolute paths or separators).
bool isStorablePatchRef(String ref) =>
    sanitizePatchRef(ref) == ref && _patchRefPattern.hasMatch(ref);

/// Returns [ref] when [isStorablePatchRef]; throws otherwise.
String checkPatchRef(String ref) {
  if (!isStorablePatchRef(ref)) {
    throw ArgumentError.value(ref, 'ref', 'not a retouch/<name>.png ref');
  }
  return ref;
}

/// RGBA patches of heal ops, stored as PNG at `assets/<assetId>/<ref>`.
///
/// Implementations: [MemoryPatchStore] (web, tests) and `FilePatchStore`
/// (native, next to the catalog). Encoding and decoding run off the UI
/// isolate.
abstract interface class PatchStore {
  /// Writes [rgba] (straight alpha) as a PNG. Throws [ArgumentError] for an
  /// unsafe [assetId] or [ref].
  Future<void> save(String assetId, String ref, RgbaBuffer rgba);

  /// The decoded patch, or null when it is missing, unreadable, or [ref] is
  /// not a storable ref (documents are untrusted input).
  Future<RgbaBuffer?> load(String assetId, String ref);

  /// Refs of every stored patch for [assetId].
  Future<Set<String>> list(String assetId);

  /// Deletes one patch (no-op when missing).
  Future<void> delete(String assetId, String ref);

  /// Copies the stored PNG [fromRef] of [fromAsset] to [toRef] of [toAsset]
  /// byte for byte. False when the source is missing or unsafe; throws
  /// [ArgumentError] for an unsafe target.
  Future<bool> copy(
    String fromAsset,
    String fromRef,
    String toAsset,
    String toRef,
  );
}

/// Opens the store lazily, so callers only touch it when a photo has heal
/// ops (tests and photos without retouching never need a store).
typedef PatchStoreGetter = Future<PatchStore> Function();

/// Every patch ref [doc] can still render: the current settings, both sides
/// of every history entry (undo and redo), snapshots and the AI record's
/// settings. Hidden ops count (they can be shown again).
Set<String> referencedPatchRefs(EditDocument doc) {
  final refs = <String>{};
  void addOps(Iterable<HealOp> ops) {
    for (final op in ops) {
      if (op.patch.isNotEmpty) refs.add(op.patch);
    }
  }

  // Background-swap images live in the same store.
  void addBackdrop(BackdropChange b) {
    if (b.imageRef.isNotEmpty) refs.add(b.imageRef);
  }

  void addSettings(DevelopSettings s) {
    addOps(s.heal);
    addBackdrop(s.backdrop);
  }

  addSettings(doc.settings);
  for (final entry in doc.history.entries) {
    for (final op in entry.ops) {
      if (op.path == 'heal') {
        addOps(parseHealOps(op.from));
        addOps(parseHealOps(op.to));
      } else if (op.path == 'backdrop') {
        addBackdrop(BackdropChange.fromJson(op.from));
        addBackdrop(BackdropChange.fromJson(op.to));
      }
    }
  }
  for (final snap in doc.snapshots) {
    addSettings(snap.settings);
  }
  final ai = doc.ai;
  if (ai != null) {
    addSettings(ai.preAi);
    final post = ai.postAi;
    if (post != null) addSettings(post);
  }
  return refs;
}

/// Deletes the stored patches of [doc]'s asset that [referencedPatchRefs]
/// does not list (nor [protect], e.g. patches of a run not committed yet).
/// Returns the deleted refs.
Future<Set<String>> collectPatchGarbage(
  PatchStore store,
  EditDocument doc, {
  Set<String> protect = const {},
}) async {
  final keep = {...referencedPatchRefs(doc), ...protect};
  final dead = (await store.list(doc.assetId)).difference(keep);
  for (final ref in dead) {
    await store.delete(doc.assetId, ref);
  }
  return dead;
}

/// Decoded patches of [ops]' visible, renderable ops keyed by ref (missing
/// or unreadable patches are left out). Loads a few at a time, since each
/// decode is a background isolate.
Future<Map<String, RgbaBuffer>> loadPatchMap(
  PatchStore store,
  String assetId,
  Iterable<HealOp> ops, {
  int parallel = 4,
}) async {
  final refs = {
    for (final op in ops)
      if (!op.hidden && op.isRenderable) op.patch,
  }.toList();
  final out = <String, RgbaBuffer>{};
  for (var i = 0; i < refs.length; i += parallel) {
    final batch = refs.sublist(i, (i + parallel).clamp(0, refs.length));
    final loaded = await Future.wait([
      for (final r in batch) store.load(assetId, r),
    ]);
    for (var j = 0; j < batch.length; j++) {
      final patch = loaded[j];
      if (patch != null) out[batch[j]] = patch;
    }
  }
  return out;
}

/// Encodes [rgba] as an 8-bit RGBA PNG (synchronous; see
/// [encodePatchPngInBackground]).
Uint8List encodePatchPng(RgbaBuffer rgba) {
  final image = img.Image.fromBytes(
    width: rgba.width,
    height: rgba.height,
    bytes: rgba.data.buffer,
    bytesOffset: rgba.data.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// Decodes a PNG into an 8-bit RGBA buffer. Throws [FormatException] when
/// the bytes are not a PNG.
RgbaBuffer decodePatchPng(Uint8List bytes) {
  img.Image? image;
  try {
    image = img.decodePng(bytes);
  } on Object catch (e) {
    // Damaged files throw range/state errors from the decoder; the bytes
    // are untrusted, so any failure means "unreadable".
    throw FormatException('damaged PNG patch ($e)');
  }
  if (image == null) throw const FormatException('not a PNG patch');
  if (image.numChannels != 4 || image.format != img.Format.uint8) {
    image = image.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
  }
  return RgbaBuffer(
    image.width,
    image.height,
    Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgba)),
  );
}

/// [encodePatchPng] on a background isolate.
Future<Uint8List> encodePatchPngInBackground(RgbaBuffer rgba) =>
    runInBackground(() => encodePatchPng(rgba));

/// [decodePatchPng] on a background isolate; null for unreadable bytes.
Future<RgbaBuffer?> decodePatchPngInBackground(Uint8List bytes) =>
    runInBackground(() {
      try {
        return decodePatchPng(bytes);
      } on FormatException {
        return null;
      }
    });
