import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_analyzer.dart' show BackgroundRunner;
import 'package:lumen/ai/ondevice/face_model_bindings.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/platform/background.dart';

/// Per-face parsing for the retouch skin masks: Selfie Multiclass run on
/// each face tile (the face, its hairline, ears, neck and anything else
/// inside the tile), turned into [FaceParsingPlanes] over exactly the
/// tile's source rect. Tensor preparation and decoding run off the UI
/// isolate; inference runs in the session's own worker.
class FaceParser {
  FaceParser({
    required InferenceSession session,
    required this.spec,
    BackgroundRunner? runner,
  }) : _session = session,
       _run = runner ?? runInBackground,
       _input = resolveImageInput(session, spec, TensorRange.minusOneToOne),
       _output = _resolveOutput(session, spec);

  final ModelSpec spec;
  final InferenceSession _session;
  final BackgroundRunner _run;
  final ImageInput _input;
  final ({String name, int channels}) _output;

  static ({String name, int channels}) _resolveOutput(
    InferenceSession s,
    ModelSpec spec,
  ) {
    final name = spec.outputWithRole(TensorRoles.segmentation)?.name;
    final t = name == null
        ? s.outputs.firstOrNull
        : s.outputs.firstWhereOrNull((t) => t.name == name);
    if (t == null || t.shape.length != 4 || t.shape[3] <= SelfieClass.clothes) {
      throw ModelContractMismatch(
        '${spec.key}: no [1, H, W, ≥5] segmentation output (${s.outputs})',
      );
    }
    return (name: t.name, channels: t.shape[3]);
  }

  /// Parses every tile (in order). Throws an [InferenceException] when a
  /// run fails.
  Future<List<FaceParsingPlanes>> parse(List<FaceTileImage> tiles) async {
    final out = <FaceParsingPlanes>[];
    final i = _input, channels = _output.channels;
    for (final t in tiles) {
      final pixels = t.pixels;
      final tensor = await _run(
        () => letterboxToTensor(
          pixels,
          width: i.width,
          height: i.height,
          range: i.range,
        ),
      );
      final result = await _session.run({i.name: tensor.data});
      final raw = result[_output.name];
      if (raw == null) {
        throw InferenceRunFailed('${spec.key} returned no segmentation');
      }
      final plan = t.plan;
      out.add(
        await _run(
          () => FaceParsingPlanes.fromTile(
            plan,
            multiclassProbabilities(raw, channels),
            width: tensor.width,
            height: tensor.height,
            channels: channels,
            letterbox: tensor.letterbox,
          ),
        ),
      );
    }
    return out;
  }

  Future<void> dispose() => _session.dispose();
}

/// Cache key of the parsing of [tiles] by [spec]: the model and every
/// tile's face and window (a different plan means a different parse).
String faceParsingKey(ModelSpec spec, List<FaceTilePlan> tiles) => [
  spec.key,
  for (final t in tiles)
    '${t.faceId}@${t.gridW}x${t.gridH}:${t.window.x0},${t.window.y0},'
        '${t.window.w}x${t.window.h}',
].join('|');

/// [planes] wrapped with their [key] (the cache file format).
Uint8List wrapParsing(String key, List<FaceParsingPlanes> planes) {
  final k = utf8.encode(key);
  final body = encodeParsingPlanes(planes);
  final head = ByteData(4)..setUint32(0, k.length, Endian.little);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...k, ...body]);
}

/// The planes in [bytes] when they were stored under [key], else null.
List<FaceParsingPlanes>? unwrapParsing(Uint8List bytes, String key) {
  if (bytes.length < 4) return null;
  final n = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
  if (4 + n > bytes.length) return null;
  try {
    if (utf8.decode(bytes.sublist(4, 4 + n)) != key) return null;
  } on FormatException {
    return null;
  }
  return decodeParsingPlanes(Uint8List.sublistView(bytes, 4 + n));
}
