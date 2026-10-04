import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/export/backdrop_export.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/remove/heal_transfer.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/import/photo_decoder.dart';

/// Long edge a picked backdrop image is stored at.
const int kBackdropImageEdge = 2048;

/// Background-swap inputs for the open photo: loaded only while a swap is
/// on (segmentation runs then), reloaded when the image changes.
final backdropInputsProvider = FutureProvider.family<BackdropInputs, String>((
  ref,
  assetId,
) async {
  final key = ref.watch(
    editorProvider(assetId).select((s) {
      final b = s.value?.settings.backdrop;
      if (b == null || b.isNone) return null;
      return (image: b.mode == BackdropMode.image ? b.imageRef : '');
    }),
  );
  if (key == null) return kNoBackdropInputs;
  final change = ref.read(editorProvider(assetId)).value!.settings.backdrop;
  return backdropInputsLoader(
    source: ref.watch(aiMaskSourceProvider),
    loader: ref.watch(aiMaskRasterLoaderProvider),
    patches: () => ref.read(patchStoreProvider.future),
  )(assetId, change);
});

/// Lets the user pick a backdrop image, stores it with the photo (like heal
/// patches) and switches the background swap to it. False when cancelled or
/// the file is not a readable image.
Future<bool> chooseBackdropImage(WidgetRef ref, String assetId) async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Choose a background',
    type: FileType.image,
  );
  final file = picked.isEmpty ? null : picked.first;
  final bytes = await file?.xFile.readAsBytes();
  if (bytes == null) return false;
  final RgbaBuffer rgba;
  try {
    final img = await decodePhoto(bytes, maxLongEdge: kBackdropImageEdge);
    try {
      rgba = await rgbaFromImage(img);
    } finally {
      img.dispose();
    }
  } on Exception {
    return false;
  }
  final state = ref.read(editorProvider(assetId)).value;
  if (state == null) return false;
  final id = newHealOpIds(referencedPatchRefs(state.doc), 1).single;
  final imageRef = '$kRetouchDir/bg$id.png';
  final store = await ref.read(patchStoreProvider.future);
  await store.save(assetId, imageRef, rgba);
  final s = ref.read(editorProvider(assetId)).value?.settings;
  if (s == null) return false;
  ref
      .read(editorProvider(assetId).notifier)
      .commit(
        s.copyWith(
          backdrop: s.backdrop.copyWith(
            mode: BackdropMode.image,
            imageRef: imageRef,
          ),
        ),
        label: 'Background image',
      );
  return true;
}
