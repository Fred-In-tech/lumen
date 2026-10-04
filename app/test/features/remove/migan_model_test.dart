// Real-model test: MI-GAN through LiteRtBackend on a synthetic scene (no
// real photo, no download).
//
// Needs `.dev_models/migan_fp16.tflite` (repo root, see
// docs/MODEL_LICENSES.md) and the LiteRT host libraries (TFLITE_LIB_PATH and
// LITERT_LIB_PATH, exported by tool/verify.sh). Skips cleanly without them.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/litert_backend_io.dart';
import 'package:lumen/features/remove/migan_inpaint_model.dart';
import 'package:lumen_core/lumen_core.dart';

const _model = '../.dev_models/migan_fp16.tflite';

final Object _skip =
    Platform.environment['TFLITE_LIB_PATH'] == null ||
        Platform.environment['LITERT_LIB_PATH'] == null
    ? 'LiteRT host libraries not configured (run tool/verify.sh)'
    : !File(_model).existsSync()
    ? 'MI-GAN not downloaded to .dev_models'
    : false;

/// Sky-to-ground gradient with soft horizontal bands and fine grain.
RgbaBuffer _scene(int w, int h) {
  final b = RgbaBuffer(w, h);
  final rnd = math.Random(3);
  for (var y = 0; y < h; y++) {
    final t = y / h;
    final band = 10 * math.sin(y / 9);
    for (var x = 0; x < w; x++) {
      final n = rnd.nextInt(9) - 4;
      b.setPixel(
        x,
        y,
        (90 + 110 * t + band + n).round().clamp(0, 255),
        (140 + 40 * t + band + n).round().clamp(0, 255),
        (210 - 120 * t + n).round().clamp(0, 255),
      );
    }
  }
  return b;
}

/// Mean absolute error over the hole (keep == 0), RGB.
double _holeMae(RgbaBuffer a, RgbaBuffer b, Uint8List keep) {
  var sum = 0.0, n = 0;
  for (var i = 0; i < keep.length; i++) {
    if (keep[i] != 0) continue;
    for (var c = 0; c < 3; c++) {
      sum += (a.data[i * 4 + c] - b.data[i * 4 + c]).abs();
    }
    n += 3;
  }
  return sum / n;
}

void main() {
  test('MI-GAN fills a hole far better than a mean fill', () async {
    final session = await loadVerifiedSession(
      const LiteRtBackend(),
      kMiganSpec,
      const ModelFileSource(_model),
    );
    final model = MiganInpaintModel(session);
    addTearDown(model.dispose);

    final truth = _scene(512, 512);
    final keep = Uint8List(512 * 512)..fillRange(0, 512 * 512, 255);
    for (var y = 0; y < 512; y++) {
      for (var x = 0; x < 512; x++) {
        if ((x - 256) * (x - 256) + (y - 300) * (y - 300) < 70 * 70) {
          keep[y * 512 + x] = 0;
        }
      }
    }
    // The model must not see the hole's pixels: paint them black.
    final input = truth.copy();
    var mean = [0.0, 0.0, 0.0];
    var known = 0;
    for (var i = 0; i < keep.length; i++) {
      if (keep[i] == 0) {
        input.data.fillRange(i * 4, i * 4 + 3, 0);
      } else {
        for (var c = 0; c < 3; c++) {
          mean[c] += truth.data[i * 4 + c];
        }
        known++;
      }
    }
    mean = [for (final m in mean) m / known];
    final meanFill = truth.copy();
    for (var i = 0; i < keep.length; i++) {
      if (keep[i] == 0) {
        for (var c = 0; c < 3; c++) {
          meanFill.data[i * 4 + c] = mean[c].round();
        }
      }
    }

    await model.inpaint(input, keep); // warm-up
    final sw = Stopwatch()..start();
    final out = await model.inpaint(input, keep);
    final ms = sw.elapsedMilliseconds;

    final mae = _holeMae(out, truth, keep);
    final baseline = _holeMae(meanFill, truth, keep);
    debugPrint(
      'MI-GAN 512² inference ${ms}ms; hole MAE ${mae.toStringAsFixed(1)} '
      'vs mean fill ${baseline.toStringAsFixed(1)}',
    );
    expect(mae, lessThan(baseline * 0.6));
    // Known pixels come back close to the input (the pipeline only keeps
    // the hole, but a broken layout would scramble everything).
    final o = out.offset(20, 20);
    expect((out.data[o] - truth.data[o]).abs(), lessThan(40));
  }, skip: _skip);

  test('pipeline with MI-GAN on a 1600×1200 photo (timing)', () async {
    final session = await loadVerifiedSession(
      const LiteRtBackend(),
      kMiganSpec,
      const ModelFileSource(_model),
    );
    final model = MiganInpaintModel(session);
    addTearDown(model.dispose);
    final src = _scene(1600, 1200);
    final hole = HoleMask.fromPixels(1600, 1200, [
      for (var y = 500; y < 700; y++)
        for (var x = 700; x < 900; x++) (x, y),
    ]);
    final sw = Stopwatch()..start();
    final res = await InpaintPipeline.remove(src, hole, model: model);
    debugPrint(
      'pipeline (model + upsample + detail) on 200×200 hole: '
      '${sw.elapsedMilliseconds}ms, engine ${res.engineId}',
    );
    expect(res.ai, isTrue);
    expect(res.engineId, MiganInpaintModel.engineId);
    final healed = composeHealed(
      src,
      [
        for (final p in res.patches)
          HealOp.forPatch(
            id: 'x${p.bbox.x}',
            bbox: p.bbox,
            srcWidth: 1600,
            srcHeight: 1200,
            engine: res.engineId,
            ai: true,
            strokes: const [],
          ),
      ],
      MapPatchLookup({
        for (final p in res.patches) 'retouch/x${p.bbox.x}.png': p.rgba,
      }),
    );
    // The fill continues the gradient: the hole's centre row matches the
    // rows just above and below it on average.
    double rowMean(int y) {
      var s = 0.0;
      for (var x = 720; x < 880; x++) {
        s += healed.data[healed.offset(x, y)];
      }
      return s / 160;
    }

    expect(rowMean(600), closeTo((rowMean(495) + rowMean(705)) / 2, 20));
  }, skip: _skip);

  test('tensor packing matches the pinned layout', () {
    final crop = RgbaBuffer.filled(512, 512, 255, 0, 128);
    final keep = Uint8List(512 * 512)..fillRange(0, 1000, 255);
    final x = miganInput(crop, keep);
    const n = 512 * 512;
    expect(x.length, 4 * n);
    expect(x[0], 0.5); // kept: mask − 0.5
    expect(x[n], 1.0); // red 255 → 1
    expect(x[2 * n], -1.0); // green 0 → −1
    expect(x[3 * n], closeTo(0.0039, 1e-3)); // blue 128 → ~0
    expect(x[2000], -0.5); // hole
    expect(x[n + 2000], 0.0); // rgb · 0
    final out = Float32List(3 * n)..fillRange(0, n, 2.0); // red clamps to 1
    final rgba = miganOutput(out, 512, 512);
    expect(rgba.data.sublist(0, 4), [255, 128, 128, 255]);
  });
}
