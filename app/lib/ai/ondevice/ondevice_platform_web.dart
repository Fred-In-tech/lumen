import 'package:lumen/ai/ondevice/ai_raster_store.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_parsing_cache.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/platform/platform_info.dart';

/// Web demo: no on-device models.
InferenceBackend createInferenceBackend(PlatformInfo platform) =>
    const UnavailableInferenceBackend('on-device models are not on web');

Future<ModelStore> openModelStore(
  PlatformInfo platform, {
  BundledModelLoader? bundled,
}) =>
    Future.error(const InferenceUnavailable('on-device models are not on web'));

Future<FaceCache> openFaceCache() async => MemoryFaceCache();

Future<AiRasterStore> openAiRasterStore() async => MemoryAiRasterStore();

Future<FaceParsingCache> openFaceParsingCache() async =>
    MemoryFaceParsingCache();
