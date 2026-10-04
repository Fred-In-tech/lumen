import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_images.dart';

/// A stand-in for MI-GAN: records its inputs and paints the hole green.
class FakeModel implements InpaintModel {
  final inputs = <(int, int)>[];
  final holeCounts = <int>[];

  @override
  String get id => 'fake-gan@1';

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keepMask) async {
    inputs.add((crop.width, crop.height));
    holeCounts.add(keepMask.where((v) => v == 0).length);
    final out = crop.copy();
    for (var i = 0; i < keepMask.length; i++) {
      if (keepMask[i] != 0) continue;
      out.data.setRange(i * 4, i * 4 + 4, [30, 200, 40, 255]);
    }
    return out;
  }
}

class BadModel implements InpaintModel {
  @override
  String get id => 'bad@1';

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keepMask) async =>
      RgbaBuffer(10, 10);
}

/// [src] with every patch alpha-blended on top (straight alpha, 8-bit).
RgbaBuffer applyPatches(RgbaBuffer src, List<InpaintPatch> patches) {
  final out = src.copy();
  for (final p in patches) {
    for (var y = 0; y < p.bbox.height; y++) {
      for (var x = 0; x < p.bbox.width; x++) {
        final s = (y * p.bbox.width + x) * 4;
        final a = p.rgba.data[s + 3];
        final o = out.offset(p.bbox.x + x, p.bbox.y + y);
        for (var c = 0; c < 3; c++) {
          out.data[o + c] =
              (p.rgba.data[s + c] * a + out.data[o + c] * (255 - a) + 127) ~/
              255;
        }
      }
    }
  }
  return out;
}

/// Texture with a red "object" disc painted at ([cx], [cy]).
(RgbaBuffer, RgbaBuffer) scene(int w, int h, int cx, int cy, int r) {
  final gt = grainTexture(w, h, grain: 6).toRgba();
  final src = gt.copy();
  for (var y = cy - r; y <= cy + r; y++) {
    for (var x = cx - r; x <= cx + r; x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
        src.setPixel(x, y, 250, 10, 10);
      }
    }
  }
  return (gt, src);
}

HoleMask disc(int w, int h, int cx, int cy, int r) =>
    HoleMask.fromPixels(w, h, [
      for (var y = cy - r; y <= cy + r; y++)
        for (var x = cx - r; x <= cx + r; x++)
          if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) (x, y),
    ]);

double regionMae(RgbaBuffer a, RgbaBuffer b, HoleMask m) {
  var sum = 0.0, n = 0;
  for (var y = m.bbox.y; y < m.bbox.bottom; y++) {
    for (var x = m.bbox.x; x < m.bbox.right; x++) {
      if (!m.isHole(x, y)) continue;
      sum += (a.r(x, y) - b.r(x, y)).abs() + (a.g(x, y) - b.g(x, y)).abs();
      n += 2;
    }
  }
  return sum / n;
}

void main() {
  group('InpaintPipeline.remove (classical)', () {
    test('removes the object; pixels outside the feathered hole are '
        'bit-identical', () async {
      final (gt, src) = scene(700, 500, 300, 240, 22);
      final hole = disc(700, 500, 300, 240, 24);
      final res = await InpaintPipeline.remove(
        src,
        hole,
        method: InpaintMethod.patchMatch,
      );
      expect(res.engineId, 'patchmatch@1');
      expect(res.ai, isFalse);
      expect(res.patches, hasLength(1));
      final healed = applyPatches(src, res.patches);
      expect(regionMae(healed, gt, hole), lessThan(12));
      final p = res.patches.single;
      var changedOutside = 0;
      for (var y = 0; y < 500; y++) {
        for (var x = 0; x < 700; x++) {
          final inPatch = p.bbox.contains(x, y);
          final a = inPatch
              ? p.rgba.data[((y - p.bbox.y) * p.bbox.width + x - p.bbox.x) * 4 +
                    3]
              : 0;
          if (a != 0) continue;
          final o = src.offset(x, y);
          for (var c = 0; c < 4; c++) {
            if (healed.data[o + c] != src.data[o + c]) changedOutside++;
          }
        }
      }
      expect(changedOutside, 0);
      // The hole itself is fully opaque in the patch.
      final cx = 300 - p.bbox.x, cy = 240 - p.bbox.y;
      expect(p.rgba.data[(cy * p.bbox.width + cx) * 4 + 3], 255);
    });

    test(
      'auto-picks Telea for a scratch and push-pull for a dust spot',
      () async {
        final src = grainTexture(600, 400, grain: 3).toRgba();
        final scratchMask = HoleMask.fromPixels(600, 400, [
          for (var x = 200; x < 400; x++)
            for (var y = 200; y < 203; y++) (x, y),
        ]);
        final a = await InpaintPipeline.remove(src, scratchMask);
        expect(a.method, InpaintMethod.telea);
        final spot = await InpaintPipeline.remove(
          src,
          disc(600, 400, 300, 100, 9),
        );
        expect(spot.method, InpaintMethod.pushPull);
        expect(spot.patches.single.bbox.width, lessThan(60));
      },
    );

    test('several disjoint holes give one patch per crop', () async {
      final src = grainTexture(2000, 900, grain: 4).toRgba();
      final m = HoleMask.fromPixels(2000, 900, [
        for (var y = 292; y <= 308; y++)
          for (var x = 192; x <= 208; x++) (x, y),
        for (var y = 592; y <= 608; y++)
          for (var x = 1692; x <= 1708; x++) (x, y),
      ]);
      final res = await InpaintPipeline.remove(
        src,
        m,
        method: InpaintMethod.pushPull,
      );
      expect(res.patches, hasLength(2));
      for (final p in res.patches) {
        expect(p.bbox.x >= 0 && p.bbox.right <= 2000, isTrue);
        expect(p.rgba.width, p.bbox.width);
      }
      expect(res.patches[0].bbox.overlaps(res.patches[1].bbox), isFalse);
    });

    test('deterministic for a fixed seed', () async {
      final (_, src) = scene(400, 300, 200, 150, 15);
      final hole = disc(400, 300, 200, 150, 17);
      final a = await InpaintPipeline.remove(
        src,
        hole,
        method: InpaintMethod.patchMatch,
      );
      final b = await InpaintPipeline.remove(
        src,
        hole,
        method: InpaintMethod.patchMatch,
      );
      expect(a.patches.single.rgba.data, b.patches.single.rgba.data);
    });
  });

  group('InpaintPipeline.remove (model)', () {
    test(
      'feeds the model 512 crops with keep = 255 and restores detail',
      () async {
        final (_, src) = scene(1600, 1200, 800, 600, 150);
        final hole = disc(1600, 1200, 800, 600, 152);
        final model = FakeModel();
        final res = await InpaintPipeline.remove(src, hole, model: model);
        expect(res.method, InpaintMethod.model);
        expect(res.ai, isTrue);
        expect(res.engineId, 'fake-gan@1');
        expect(model.inputs, [(512, 512)]);
        expect(model.holeCounts.single, greaterThan(1000));
        final healed = applyPatches(src, res.patches);
        // Model colour (green) inside, with grain restored from the ring.
        final g = healed.g(800, 600), r = healed.r(800, 600);
        expect(g, greaterThan(140));
        expect(r, lessThan(90));
        var lo = 255, hi = 0;
        for (var x = 780; x < 820; x++) {
          lo = healed.g(x, 600) < lo ? healed.g(x, 600) : lo;
          hi = healed.g(x, 600) > hi ? healed.g(x, 600) : hi;
        }
        expect(hi - lo, greaterThan(6), reason: 'grain restored, not flat');
      },
    );

    test('below 1.5x upscale the model output is used as is', () async {
      final (_, src) = scene(1600, 1200, 800, 600, 110); // crop 672: 1.31x
      final res = await InpaintPipeline.remove(
        src,
        disc(1600, 1200, 800, 600, 112),
        model: FakeModel(),
      );
      final healed = applyPatches(src, res.patches);
      for (var x = 780; x < 820; x++) {
        expect(healed.g(x, 600), 200, reason: 'flat model green, no detail');
      }
    });

    test('rejects a model that returns the wrong size', () async {
      final (_, src) = scene(600, 600, 300, 300, 60);
      expect(
        () => InpaintPipeline.remove(
          src,
          disc(600, 600, 300, 300, 62),
          model: BadModel(),
        ),
        throwsStateError,
      );
    });
  });

  test('runInpaintJob: isolate-safe plain-data entry point', () async {
    final (_, src) = scene(500, 400, 250, 200, 12);
    final job = InpaintJob(
      source: src,
      strokes: const [
        BrushStroke(points: [(0.5, 0.5)], radius: 0.03, hardness: 1),
      ],
      config: const InpaintConfig(seed: 3),
    );
    final res = await runInpaintJob(job);
    expect(res.patches, isNotEmpty);
    expect(res.ai, isFalse);
  });

  group('clone and heal patches', () {
    test('clonePatch copies the offset area into the hole', () {
      final src = grainTexture(200, 150).toRgba();
      final hole = disc(200, 150, 100, 75, 8);
      final p = clonePatch(src, hole, (40, 0), featherPx: 3)!;
      final healed = applyPatches(src, [p]);
      expect(
        healed.data.sublist(src.offset(100, 75), src.offset(100, 75) + 3),
        src.data.sublist(src.offset(140, 75), src.offset(140, 75) + 3),
      );
      expect(p.bbox, hole.bbox.inflate(3));
    });

    test('healPatch keeps colour from the surroundings', () {
      final gt = grainTexture(200, 150, grain: 4);
      final src = gt.toRgba();
      for (var y = 70; y < 80; y++) {
        for (var x = 95; x < 105; x++) {
          src.setPixel(x, y, 0, 0, 0);
        }
      }
      final hole = HoleMask.fromPixels(200, 150, [
        for (var y = 69; y < 81; y++)
          for (var x = 94; x < 106; x++) (x, y),
      ]);
      final healed = applyPatches(src, [healPatch(src, hole)!]);
      expect((healed.g(100, 75) - gt.at(100, 75, 1)).abs(), lessThan(20));
    });
  });
}
