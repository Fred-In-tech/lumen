import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/backdrop_scene.dart';

void main() {
  final scene = SwapScene.make();
  final base = BackdropBase.build(scene.image, people: scene.people);

  RgbaBuffer run(BackdropChange b, {RgbaBuffer? image}) => applyBackdrop(
    scene.image,
    BackdropAssets.build(base, b, image: image),
    b,
  );

  (int, int, int) px(RgbaBuffer b, (int, int) p) =>
      (b.r(p.$1, p.$2), b.g(p.$1, p.$2), b.b(p.$1, p.$2));

  group('matte', () {
    test('refined against the photo: sharper than the coarse raster', () {
      double raw((int, int) p) => base.rawAlphaAt(p.$1, p.$2);
      double refined((int, int) p) => base.alphaAt(p.$1, p.$2);
      final inside = scene.at(scene.r - 6, 200),
          outside = scene.at(scene.r + 9, 160);
      expect(refined(inside), greaterThan(0.95));
      expect(refined(outside), lessThan(0.05));
      expect(refined(inside), greaterThanOrEqualTo(raw(inside) - 1e-6));
      expect(refined(outside), lessThanOrEqualTo(raw(outside) + 1e-6));
      expect(base.alphaAt(2, 2), lessThan(0.02));
      expect(
        base.alphaAt(scene.cx.floor(), scene.cy.floor()),
        greaterThan(0.98),
      );
    });

    test('no rasters: an empty matte (everything is background)', () {
      final none = BackdropBase.build(scene.image);
      expect(none.alphaAt(scene.cx.floor(), scene.cy.floor()), 0);
    });

    test('old background estimate is the backdrop colour', () {
      final m = base.oldBackgroundMean;
      expect(linearToSrgb(m.g) * 255, closeTo(170, 6));
      expect(linearToSrgb(m.r) * 255, closeTo(40, 6));
    });
  });

  group('composite', () {
    const white = BackdropChange(
      mode: BackdropMode.color,
      color: 0xFFFFFFFF,
      spill: 0,
    );

    test('mode none returns the source itself', () {
      expect(identical(run(BackdropChange.none), scene.image), isTrue);
    });

    test(
      'solid colour: far background replaced, subject interior bit-exact',
      () {
        final out = run(white);
        expect(px(out, (3, 3)), (255, 255, 255));
        final c = (scene.cx.floor(), scene.cy.floor());
        expect(px(out, c), px(scene.image, c));
      },
    );

    test('remove spill takes the green cast out of the soft edge', () {
      int greenExcess(RgbaBuffer b) {
        var s = 0;
        for (var a = 0.0; a < 360; a += 7) {
          final p = scene.at(scene.r + 0.5, a);
          s += b.g(p.$1, p.$2) - (b.r(p.$1, p.$2) + b.b(p.$1, p.$2)) ~/ 2;
        }
        return s;
      }

      final noSpill = run(white);
      final spill = run(white.copyWith(spill: 100));
      expect(greenExcess(spill), lessThan(greenExcess(noSpill) - 200));
    });

    test('gradient runs from colour to colour2 along the angle', () {
      final out = run(
        const BackdropChange(
          mode: BackdropMode.gradient,
          color: 0xFF000000,
          color2: 0xFFFFFFFF,
          angle: 0,
          spill: 0,
        ),
      );
      expect(out.r(1, 3), lessThan(15));
      expect(out.r(scene.width - 2, 3), greaterThan(240));
    });

    test('image backdrop: fill covers, fit letterboxes with the colour', () {
      final img = RgbaBuffer.filled(100, 400, 200, 30, 30); // tall image
      final fill = run(
        const BackdropChange(
          mode: BackdropMode.image,
          imageRef: 'retouch/bg.png',
          spill: 0,
        ),
        image: img,
      );
      expect(px(fill, (3, 3)).$1, closeTo(200, 2));
      final fit = run(
        const BackdropChange(
          mode: BackdropMode.image,
          imageRef: 'retouch/bg.png',
          fit: BackdropFit.fit,
          color: 0xFF0000FF,
          spill: 0,
        ),
        image: img,
      );
      expect(px(fit, (2, 90)), (0, 0, 255)); // left letterbox
      expect(px(fit, (scene.width ~/ 2, 3)).$1, closeTo(200, 2));
    });

    test('blur: the subject does not bleed into the blurred background', () {
      final red = SwapScene.make(
        backdrop: const [120, 120, 120],
        subject: const [230, 30, 30],
      );
      final b = BackdropBase.build(red.image, people: red.people);
      const blur = BackdropChange(mode: BackdropMode.blur, blur: 100, spill: 0);
      final out = applyBackdrop(red.image, BackdropAssets.build(b, blur), blur);
      // Just outside the subject: still the grey backdrop, not pink.
      for (var a = 0.0; a < 360; a += 30) {
        final p = red.at(red.r + 10, a);
        expect(
          out.r(p.$1, p.$2) - out.g(p.$1, p.$2),
          lessThan(12),
          reason: 'angle $a',
        );
      }
      // A naive blur of the photo would be pink there.
      expect(_naiveBlurRedExcess(red), greaterThan(12));
    });

    test('brightness match scales the subject toward the new background', () {
      const dark = BackdropChange(
        mode: BackdropMode.color,
        color: 0xFF101010,
        spill: 0,
      );
      final c = (scene.cx.floor(), scene.cy.floor());
      final plain = run(dark);
      final matched = run(dark.copyWith(match: 100));
      expect(matched.r(c.$1, c.$2), lessThan(plain.r(c.$1, c.$2)));
    });
  });

  test('uniforms pack kBackdropFloatCount floats', () {
    const b = BackdropChange(mode: BackdropMode.color);
    final f = BackdropUniforms.pack(
      BackdropAssets.build(base, b),
      b,
      width: 10,
      height: 20,
    );
    expect(f.length, kBackdropFloatCount);
    expect(f.sublist(0, 6), [10, 20, 0, 0, 10, 20]);
    expect(f[16], 0);
    final window = BackdropUniforms.pack(
      BackdropAssets.build(base, b),
      b,
      width: 10,
      height: 20,
      tileX: 4,
      tileY: 6,
      fullWidth: 100,
      fullHeight: 80,
      sourceIsWindow: true,
    );
    expect(window.sublist(2, 6), [4, 6, 100, 80]);
    expect(window[16], 1); // uPlateB.z: the source is the pass window
  });
}

/// Red excess just outside the subject after a naive box blur of the photo.
int _naiveBlurRedExcess(SwapScene s) {
  final p = s.at(s.r + 10, 90);
  var r = 0, g = 0, n = 0;
  for (var y = p.$2 - 12; y <= p.$2 + 12; y++) {
    for (var x = p.$1 - 12; x <= p.$1 + 12; x++) {
      final xx = math.min(s.width - 1, math.max(0, x));
      final yy = math.min(s.height - 1, math.max(0, y));
      r += s.image.r(xx, yy);
      g += s.image.g(xx, yy);
      n++;
    }
  }
  return (r - g) ~/ n;
}
