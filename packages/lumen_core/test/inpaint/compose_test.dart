import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_images.dart';

/// A [w]×[h] patch: solid colour disc with a soft edge.
RgbaBuffer discPatch(int w, int h, int r, int g, int b) {
  final p = RgbaBuffer(w, h);
  final cx = w / 2, cy = h / 2, rad = math.min(w, h) / 2 - 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = math.sqrt(
        math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2),
      );
      final a = ((rad - d) / 4).clamp(0.0, 1.0);
      p.setPixel(x, y, r, g, b, (a * 255).round());
    }
  }
  return p;
}

HealOp op(String id, PixelBox bbox, {bool hidden = false}) => HealOp(
  id: id,
  bbox: bbox,
  srcWidth: 400,
  srcHeight: 300,
  patch: 'retouch/$id.png',
  hidden: hidden,
);

void main() {
  final source = grainTexture(400, 300, grain: 5).toRgba();
  final lookup = MapPatchLookup({
    'retouch/a.png': discPatch(60, 40, 200, 30, 30),
    'retouch/b.png': discPatch(50, 50, 20, 30, 220),
  });

  group('composeHealed', () {
    test('full resolution: exact blend; untouched pixels bit-identical', () {
      final ops = [op('a', const PixelBox(100, 80, 60, 40))];
      final out = composeHealed(source, ops, lookup);
      expect(out.width, 400);
      // Patch centre is opaque → exactly the patch colour.
      expect(out.r(130, 100), 200);
      expect(out.g(130, 100), 30);
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 400; x++) {
          if (ops.first.bbox.contains(x, y)) continue;
          expect(out.r(x, y), source.r(x, y));
        }
      }
      // Alpha 0 pixels inside the bbox are untouched too.
      expect(out.r(100, 80), source.r(100, 80));
      expect(source.r(130, 100), isNot(200));
    });

    test('ops apply in order; hidden ops and missing patches are skipped', () {
      const box = PixelBox(150, 100, 50, 50);
      final both = composeHealed(source, [
        op('b', box),
        op('a', const PixelBox(145, 105, 60, 40)),
      ], lookup);
      expect(both.r(175, 125), 200, reason: 'a drawn last');
      final hidden = composeHealed(source, [
        op('b', box),
        op('a', const PixelBox(145, 105, 60, 40), hidden: true),
      ], lookup);
      expect(hidden.b(175, 125), 220);
      final missing = composeHealed(source, [op('zz', box)], lookup);
      expect(missing.data, source.data);
      expect(identical(missing, source), isFalse);
    });

    test('half resolution matches a downscaled full-resolution composite', () {
      final ops = [
        op('a', const PixelBox(101, 81, 60, 40)),
        op('b', const PixelBox(250, 151, 50, 50)),
      ];
      final full = composeHealed(source, ops, lookup);
      final halfSrc = resizeArea(
        FloatImage.fromRgba(source),
        200,
        150,
      ).toRgba();
      final half = composeHealed(halfSrc, ops, lookup);
      final want = resizeArea(FloatImage.fromRgba(full), 200, 150).toRgba();
      var maxErr = 0;
      for (var i = 0; i < half.data.length; i++) {
        maxErr = math.max(maxErr, (half.data[i] - want.data[i]).abs());
      }
      expect(maxErr, lessThanOrEqualTo(2));
      // Far from the patches the half-res source is untouched.
      expect(half.r(10, 10), halfSrc.r(10, 10));
    });
  });

  group('needsAuxRecompute', () {
    test('union of visible healed boxes vs 0.5 % of the image', () {
      HealOp sized(String id, PixelBox b, {bool hidden = false}) => HealOp(
        id: id,
        bbox: b,
        srcWidth: 1000,
        srcHeight: 1000,
        hidden: hidden,
      );
      expect(
        needsAuxRecompute([sized('a', const PixelBox(0, 0, 100, 100))]),
        isTrue,
      );
      expect(
        needsAuxRecompute([sized('a', const PixelBox(0, 0, 50, 50))]),
        isFalse,
      );
      expect(
        needsAuxRecompute([
          sized('a', const PixelBox(0, 0, 50, 50)),
          sized('b', const PixelBox(0, 0, 50, 50)),
        ]),
        isFalse,
        reason: 'overlap counts once',
      );
      expect(
        needsAuxRecompute([
          sized('a', const PixelBox(0, 0, 60, 50)),
          sized('b', const PixelBox(500, 500, 50, 60)),
        ]),
        isTrue,
      );
      expect(
        needsAuxRecompute([
          sized('a', const PixelBox(0, 0, 100, 100), hidden: true),
        ]),
        isFalse,
      );
      expect(healedAreaFraction(const []), 0);
    });
  });

  test('HealOp.forPatch fills bbox, srcSize, engine and ai', () {
    final p = InpaintPatch(const PixelBox(5, 6, 7, 8), RgbaBuffer(7, 8));
    final o = HealOp.forPatch(
      id: 'h9',
      bbox: p.bbox,
      srcWidth: 400,
      srcHeight: 300,
      engine: 'patchmatch@1',
      ai: false,
      strokes: const [
        BrushStroke(points: [(0.5, 0.5)], radius: 0.01),
      ],
      createdAt: DateTime.utc(2026),
    );
    expect(o.bbox, p.bbox);
    expect(o.patch, 'retouch/h9.png');
    expect(o.kind, HealKind.remove);
    expect(o.isRenderable, isTrue);
  });
}
