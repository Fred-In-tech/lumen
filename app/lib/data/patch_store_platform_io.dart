import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lumen/data/file_patch_store_io.dart';
import 'package:lumen/data/patch_store.dart';

/// Patches next to the catalog (`<appSupport>/<storageId>/assets/…`).
Future<PatchStore> openPatchStore() async {
  final support = await getApplicationSupportDirectory();
  return FilePatchStore(p.join(support.path, kBrand.storageId));
}
