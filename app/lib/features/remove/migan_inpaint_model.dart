import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/inference_backend.dart';

/// The pinned MI-GAN 512 Places2 model (MIT, 16 MB, downloaded on use).
const kMiganSpec = ModelManifest.miGan;

/// MI-GAN's square input side.
const kMiganSide = 512;

/// Packs a 512² crop and its keep mask (non-zero = known pixel) into
/// MI-GAN's NCHW `[1, 4, 512, 512]` input: channel 0 is `mask − 0.5`,
/// channels 1–3 are `rgb · mask` with rgb in [−1, 1].
Float32List miganInput(RgbaBuffer crop, Uint8List keep) {
  final n = crop.width * crop.height;
  if (keep.length != n) {
    throw ArgumentError('keep mask has ${keep.length} values, expected $n');
  }
  final out = Float32List(4 * n);
  final d = crop.data;
  for (var i = 0; i < n; i++) {
    final m = keep[i] != 0 ? 1.0 : 0.0;
    out[i] = m - 0.5;
    out[n + i] = m * (d[i * 4] / 127.5 - 1);
    out[2 * n + i] = m * (d[i * 4 + 1] / 127.5 - 1);
    out[3 * n + i] = m * (d[i * 4 + 2] / 127.5 - 1);
  }
  return out;
}

/// Unpacks MI-GAN's NCHW `[1, 3, h, w]` output (clamped to [−1, 1]) into an
/// opaque RGBA buffer.
RgbaBuffer miganOutput(Float32List out, int width, int height) {
  final n = width * height;
  if (out.length != 3 * n) {
    throw ArgumentError('output has ${out.length} values, expected ${3 * n}');
  }
  final buf = RgbaBuffer(width, height);
  final d = buf.data;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < 3; c++) {
      final v = out[c * n + i].clamp(-1.0, 1.0);
      d[i * 4 + c] = ((v + 1) * 127.5).round();
    }
    d[i * 4 + 3] = 255;
  }
  return buf;
}

/// MI-GAN as an [InpaintModel] over a loaded [InferenceSession] (LiteRT's
/// `CompiledModel.runAsync`, so inference itself runs off the calling
/// isolate). Throws [ModelContractMismatch] for a session whose tensors
/// are not the pinned `[1,4,512,512] → [1,3,512,512]`.
class MiganInpaintModel implements InpaintModel {
  MiganInpaintModel(this._session)
    : _input = _single(_session.inputs, 4, 'input'),
      _output = _single(_session.outputs, 3, 'output');

  static const engineId = 'migan@fp16-1';

  final InferenceSession _session;
  final String _input;
  final String _output;

  static String _single(List<TensorSignature> t, int channels, String what) {
    const n = kMiganSide * kMiganSide;
    if (t.length != 1 || elementCount(t.single.shape) != channels * n) {
      throw ModelContractMismatch(
        '${kMiganSpec.key}: expected one $what of ${channels * n} values, '
        'got $t',
      );
    }
    return t.single.name;
  }

  @override
  String get id => engineId;

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keep) async {
    if (crop.width != kMiganSide || crop.height != kMiganSide) {
      throw ArgumentError(
        'MI-GAN takes $kMiganSide² crops, got ${crop.width}×${crop.height}',
      );
    }
    final result = await _session.run({_input: miganInput(crop, keep)});
    final out = result[_output];
    if (out == null) {
      throw const InferenceRunFailed('MI-GAN returned no image');
    }
    return miganOutput(out, kMiganSide, kMiganSide);
  }

  Future<void> dispose() => _session.dispose();
}
