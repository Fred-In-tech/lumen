import 'package:http/http.dart' as http;
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lumen/ai/ondevice/disk_space_probe_io.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_cache_io.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/litert_backend_io.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/ai/ondevice/model_store_io.dart';
import 'package:lumen/platform/platform_info.dart';

/// LiteRT on every native platform, CPU (`CompiledModel`, XNNPACK) by
/// default: the tensor contracts and timings were verified on CPU. GPU
/// (`CompiledModelConfig.auto()`) is a per-platform opt-in once parity is
/// checked.
InferenceBackend createInferenceBackend(PlatformInfo platform) =>
    const LiteRtBackend();

/// `<appSupport>/models`, with the per-platform budget and disk guard.
Future<ModelStore> openModelStore(
  PlatformInfo platform, {
  BundledModelLoader? bundled,
}) async {
  final support = await getApplicationSupportDirectory();
  return FileModelStore(
    root: p.join(support.path, 'models'),
    client: http.Client(),
    closeClientOnDispose: true,
    diskProbe: ProcessDiskSpaceProbe(platform),
    budgetBytes: ModelBudget.forPlatform(platform),
    bundled: bundled,
  );
}

/// Face cache next to the catalog (`<appSupport>/<storageId>/assets/…`).
Future<FaceCache> openFaceCache() async {
  final support = await getApplicationSupportDirectory();
  return FileFaceCache(p.join(support.path, kBrand.storageId));
}
