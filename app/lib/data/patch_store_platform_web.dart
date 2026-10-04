import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/data/patch_store.dart';

/// Web demo: patches live in memory for the session, like the catalog.
Future<PatchStore> openPatchStore() async => MemoryPatchStore();
