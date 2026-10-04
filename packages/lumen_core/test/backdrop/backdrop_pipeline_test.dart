import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/backdrop_scene.dart';

/// What the renderers rely on: when assets must be rebuilt, the one-call
/// CPU/export path and the composite's aux maps.
void main() {
  final scene = SwapScene.make();
  final base = BackdropBase.build(scene.image, people: scene.people);
  const blue = BackdropChange(mode: BackdropMode.color, color: 0xFF2050C0);

  group('assets key', () {
    final a = BackdropAssets.build(base, blue);

    test('colours, gradient, fit, spill and match are uniforms only', () {
      for (final b in [
        blue.copyWith(color: 0xFF00FF00),
        blue.copyWith(mode: BackdropMode.gradient, angle: 33),
        blue.copyWith(spill: 90, match: 40),
      ]) {
        expect(a.fits(b, null), isTrue, reason: '$b');
      }
    });

    test('edges, blur amount, mode class and the image rebuild', () {
      expect(a.fits(blue.copyWith(feather: 10), null), isFalse);
      expect(a.fits(blue.copyWith(edgeShift: 20), null), isFalse);
      const blur = BackdropChange(mode: BackdropMode.blur);
      final ab = BackdropAssets.build(base, blur);
      expect(ab.fits(blur, null), isTrue);
      expect(ab.fits(blur.copyWith(blur: 70), null), isFalse);
      const img = BackdropChange(mode: BackdropMode.image, imageRef: 'r');
      final photo = AuxMaps.proxy(scene.image, longEdge: 64);
      final ai = BackdropAssets.build(base, img, image: photo);
      expect(ai.fits(img, photo), isTrue);
      expect(ai.fits(img, AuxMaps.proxy(scene.image, longEdge: 64)), isFalse);
      expect(ai.fits(blur, null), isFalse);
    });

    test('stale assets may still render colour modes, not blur or image', () {
      final ab = BackdropAssets.build(
        base,
        const BackdropChange(mode: BackdropMode.blur),
      );
      expect(ab.canRender(blue.copyWith(feather: 3)), isTrue);
      expect(
        a.canRender(const BackdropChange(mode: BackdropMode.blur)),
        isFalse,
      );
      expect(
        a.canRender(
          const BackdropChange(mode: BackdropMode.image, imageRef: 'r'),
        ),
        isFalse,
      );
      expect(a.canRender(BackdropChange.none), isFalse);
    });
  });

  group('backdroppedSource (CPU / export in one call)', () {
    test('matches the base + assets + kernel steps', () {
      final one = backdroppedSource(scene.image, blue, people: scene.people);
      final steps = applyBackdrop(
        scene.image,
        BackdropAssets.build(base, blue),
        blue,
      );
      expect(one.data, steps.data);
    });

    test('identity when off or without rasters', () {
      expect(
        identical(
          backdroppedSource(
            scene.image,
            BackdropChange.none,
            people: scene.people,
          ),
          scene.image,
        ),
        isTrue,
      );
      expect(
        identical(backdroppedSource(scene.image, blue), scene.image),
        isTrue,
      );
    });
  });

  test('aux maps of the composite see the new background', () {
    final a = BackdropAssets.build(base, blue);
    final plain = AuxMaps.compute(AuxMaps.proxy(scene.image));
    final swapped = backdropAuxMaps(a, blue);
    expect(swapped.width, plain.width);
    expect(swapped.height, plain.height);
    var diff = 0;
    for (var i = 0; i < plain.auxA.length; i++) {
      diff += (plain.auxA[i] - swapped.auxA[i]).abs();
    }
    expect(diff, greaterThan(0));
    final composite = applyBackdrop(base.analysisProxy, a, blue);
    expect(swapped.auxA, AuxMaps.compute(composite).auxA);
  });
}
