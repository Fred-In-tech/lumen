import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

RgbaBuffer _disc(int w, int h, int r, int g, int b) {
  final p = RgbaBuffer(w, h);
  final cx = w / 2, cy = h / 2, rad = math.min(w, h) / 2 - 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = math.sqrt(
        math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2),
      );
      p.setPixel(
        x,
        y,
        r,
        g,
        b,
        (((rad - d) / 4).clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return p;
}

HealOp _op(String id, PixelBox bbox, {int w = 200, int h = 150}) => HealOp(
  id: id,
  bbox: bbox,
  srcWidth: w,
  srcHeight: h,
  patch: 'retouch/$id.png',
);

void main() {
  sourceWindowTests();
  group('CatalogEntry.bitDepth', () {
    final base = CatalogEntry(
      assetId: 'a',
      fileName: 'a.cr3',
      originalPath: 'originals/a.cr3',
      format: 'cr3',
      width: 10,
      height: 20,
      bytes: 3,
      importedAt: DateTime.utc(2026),
    );

    test('old catalogs load without it and do not gain the key', () {
      final json = base.toJson();
      expect(json.containsKey('bitDepth'), isFalse);
      expect(CatalogEntry.fromJson(json).bitDepth, isNull);
    });

    test('round-trips and survives copyWith', () {
      final e = CatalogEntry.fromJson({...base.toJson(), 'bitDepth': 14});
      expect(e.bitDepth, 14);
      expect(e.toJson()['bitDepth'], 14);
      expect(e.copyWith(rating: 3).bitDepth, 14);
    });
  });

  group('heal overlay', () {
    final lookup = MapPatchLookup({
      'retouch/a.png': _disc(60, 40, 200, 30, 30),
      'retouch/b.png': _disc(50, 50, 20, 30, 220),
    });
    final ops = [
      _op('a', const PixelBox(40, 30, 60, 40)),
      _op('b', const PixelBox(80, 50, 50, 50)),
    ];
    final source = RgbaBuffer(200, 150);
    for (var i = 0; i < source.data.length; i += 4) {
      source.data[i] = (i * 7) % 256;
      source.data[i + 1] = (i * 3) % 256;
      source.data[i + 2] = (i * 11) % 256;
      source.data[i + 3] = 255;
    }

    test('overlay over the source equals composeHealed (within a level)', () {
      final healed = composeHealed(source, ops, lookup);
      final overlay = composeHealOverlay(200, 150, ops, lookup);
      final out = composeOverlayFloat(
        FloatBuffer.fromRgba(source),
        overlay,
      ).toRgba();
      var worst = 0, covered = 0;
      for (var i = 0; i < out.data.length; i++) {
        worst = math.max(worst, (out.data[i] - healed.data[i]).abs());
      }
      for (var i = 3; i < overlay.data.length; i += 4) {
        if (overlay.data[i] > 0) covered++;
        // Premultiplied: no colour above its alpha.
        expect(overlay.data[i - 1], lessThanOrEqualTo(overlay.data[i]));
      }
      expect(worst, lessThanOrEqualTo(1));
      expect(covered, greaterThan(1500));
      expect(covered, lessThan(200 * 150 ~/ 4));
    });

    test('pixels outside the patches keep their float values', () {
      final hot = FloatBuffer(200, 150);
      for (var i = 0; i < hot.data.length; i += 4) {
        hot.data
          ..[i] = 3.5
          ..[i + 1] = -0.25
          ..[i + 2] = 0.001
          ..[i + 3] = 1;
      }
      final out = composeOverlayFloat(
        hot,
        composeHealOverlay(200, 150, ops, lookup),
      );
      expect(out.data.sublist(0, 4), [3.5, -0.25, closeTo(0.001, 1e-9), 1]);
      // Opaque patch centre: the 8-bit patch colour.
      final c = out.offset(70, 50);
      expect(out.data[c], closeTo(200 / 255, 1e-6));
      expect(out.data[c + 1], closeTo(30 / 255, 1e-6));
    });

    test('scaled ops (preview size) and size mismatch', () {
      final small = composeHealOverlay(100, 75, ops, lookup);
      expect(small.data[small.offset(35, 25) + 3], 255);
      expect(small.data[3], 0);
      expect(
        () => composeOverlayFloat(FloatBuffer(4, 4), small),
        throwsArgumentError,
      );
    });
  });

  group('develop uniforms of the float path', () {
    const ctx = DevelopContext(
      outWidth: 64,
      outHeight: 32,
      sourceWidth: 400,
      sourceHeight: 200,
      auxWidth: 4,
      auxHeight: 2,
      profile: HbdProfile.rawExtended,
      windowX: 100,
      windowY: 50,
      windowWidth: 200,
      windowHeight: 50,
    );

    test('profile and window pack into uGradeParams.zw and uSrcWin', () {
      final f = DevelopUniforms.pack(DevelopSettings.defaults, ctx);
      expect(f[DevelopIndex.shoulderKnee], closeTo(0.86, 1e-6));
      expect(f[DevelopIndex.highlightGain], 0.5);
      expect(f.sublist(198, 202), [0.25, 0.25, 2, 4]);
      expect((ctx.windowWidth, ctx.windowHeight), (200, 50));
    });

    test('HbdProfile equality', () {
      expect(HbdProfile.none.isNone, isTrue);
      expect(HbdProfile.rawExtended.isNone, isFalse);
      expect(
        const HbdProfile(shoulderKnee: 0.86, highlightGain: 0.5),
        HbdProfile.rawExtended,
      );
      expect(HbdProfile.rawExtended.hashCode, isNot(HbdProfile.none.hashCode));
      expect('${HbdProfile.none}', contains('knee 0'));
    });
  });

  group('FloatBuffer.crop', () {
    test('copies a window and rejects one outside the image', () {
      final b = FloatBuffer(4, 3);
      for (var i = 0; i < 12; i++) {
        b.setPixel(i % 4, i ~/ 4, i.toDouble(), 0, 0);
      }
      final c = b.crop(1, 1, 2, 2);
      expect([c.data[0], c.data[4], c.data[8], c.data[12]], [5, 6, 9, 10]);
      expect(c.pixelCount, 4);
      expect(() => b.crop(3, 0, 2, 1), throwsRangeError);
    });
  });
}

// ---- sourceWindowFor -------------------------------------------------------

Float32List _floats(
  Geometry g, {
  int sw = 400,
  int sh = 300,
  double warpRange = 0,
}) {
  final size = outputSizeFor(sw, sh, g);
  return DevelopUniforms.pack(
    DevelopSettings.defaults.copyWith(geometry: g),
    DevelopContext(
      outWidth: size.width,
      outHeight: size.height,
      sourceWidth: sw,
      sourceHeight: sh,
      auxWidth: 1,
      auxHeight: 1,
      warpWidth: warpRange > 0 ? 8 : 1,
      warpHeight: warpRange > 0 ? 8 : 1,
      warpRange: warpRange,
    ),
  );
}

void sourceWindowTests() {
  group('sourceWindowFor', () {
    test('identity geometry: the tile itself plus the margin, clipped', () {
      final f = _floats(const Geometry());
      expect(sourceWindowFor(f, x0: 100, y0: 50, x1: 200, y1: 150, margin: 4), (
        x: 96,
        y: 46,
        width: 108,
        height: 108,
      ));
      expect(sourceWindowFor(f, x0: 0, y0: 0, x1: 400, y1: 300, margin: 4), (
        x: 0,
        y: 0,
        width: 400,
        height: 300,
      ));
    });

    test('every pixel of a tile samples inside its window', () {
      final rnd = math.Random(7);
      for (var k = 0; k < 40; k++) {
        final l = rnd.nextDouble() * 0.3, t = rnd.nextDouble() * 0.3;
        final g = Geometry(
          crop: CropRect(
            l,
            t,
            l + 0.4 + rnd.nextDouble() * 0.3,
            t + 0.4 + rnd.nextDouble() * 0.3,
          ),
          angle: rnd.nextDouble() * 20 - 10,
          rotate90: rnd.nextInt(4),
          flipH: rnd.nextBool(),
          flipV: rnd.nextBool(),
        );
        final f = _floats(g);
        final ow = f[DevelopIndex.tile + 2], oh = f[DevelopIndex.tile + 3];
        final tx0 = (rnd.nextDouble() * ow * 0.5).floorToDouble();
        final ty0 = (rnd.nextDouble() * oh * 0.5).floorToDouble();
        final tx1 = math.min(ow, tx0 + 64), ty1 = math.min(oh, ty0 + 64);
        final w = sourceWindowFor(f, x0: tx0, y0: ty0, x1: tx1, y1: ty1);
        for (var y = ty0; y < ty1; y += 3) {
          for (var x = tx0; x < tx1; x += 3) {
            final (u, v) = sourceUvFor((x + 0.5) / ow, (y + 0.5) / oh, f);
            if (u < 0 || u > 1 || v < 0 || v > 1) continue;
            expect(u * 400, inInclusiveRange(w.x - 1e-6, w.x + w.width + 1e-6));
            expect(
              v * 300,
              inInclusiveRange(w.y - 1e-6, w.y + w.height + 1e-6),
            );
          }
        }
      }
    });

    test('a warp grows the window by its range', () {
      final plain = sourceWindowFor(
        _floats(const Geometry()),
        x0: 100,
        y0: 100,
        x1: 200,
        y1: 200,
      );
      final warped = sourceWindowFor(
        _floats(const Geometry(), warpRange: 0.05),
        x0: 100,
        y0: 100,
        x1: 200,
        y1: 200,
      );
      // 0.05 uv = 20 px wide, 15 px high (float rounding may add one).
      expect(plain.x - warped.x, inInclusiveRange(20, 21));
      expect(warped.width - plain.width, inInclusiveRange(40, 42));
      expect(plain.y - warped.y, inInclusiveRange(15, 16));
      expect(warped.height - plain.height, inInclusiveRange(30, 32));
    });

    test('a rectangle outside the source gives an edge pixel', () {
      final f = _floats(const Geometry());
      final w = sourceWindowFor(f, x0: 900, y0: 900, x1: 950, y1: 950);
      expect((w.width, w.height), (1, 1));
      expect((w.x, w.y), (399, 299));
    });
  });
}
