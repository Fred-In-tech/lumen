import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140);

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;

  setUpAll(() {
    p = renderSynthPortrait(512, 512, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
  });

  double at(RetouchChannel c, double x, double y) {
    final q = _face.toPx(x, y);
    return regionAt(maps, c, q.x.floor(), q.y.floor(), 512, 512);
  }

  group('region maps cover the expected areas', () {
    test('skin covers cheeks, chin and the extended forehead', () {
      for (final (x, y) in const [
        (0.55, 0.15),
        (-0.75, 0.45),
        (0.0, 1.75),
        (0.0, -0.95),
        (0.6, -0.7),
      ]) {
        expect(
          at(RetouchChannel.skin, x, y),
          greaterThan(0.85),
          reason: '$x,$y',
        );
      }
    });

    test('skin excludes eyes, brows, lips, nostrils, hair and background', () {
      for (final (x, y) in [
        (-0.5, 0.0),
        (0.6, 0.0),
        (-0.5, -0.37),
        (0.0, 1.03),
        (0.0, 1.13),
        (-kNostrilX, kNostrilY),
        (0.0, -1.3),
        (0.0, -1.12),
        (-1.4, 1.6),
      ]) {
        expect(at(RetouchChannel.skin, x, y), lessThan(0.1), reason: '$x,$y');
      }
      expect(regionAt(maps, RetouchChannel.skin, 3, 3, 512, 512), 0);
    });

    test('under-eye crescents sit below the lower lids, not in the eyes', () {
      expect(at(RetouchChannel.underEye, -0.5, 0.15), greaterThan(0.5));
      expect(at(RetouchChannel.underEye, 0.5, 0.15), greaterThan(0.5));
      expect(at(RetouchChannel.underEye, -0.5, 0.0), lessThan(0.05));
      expect(at(RetouchChannel.underEye, -0.5, -0.2), lessThan(0.05));
      expect(at(RetouchChannel.underEye, 0.0, 0.6), 0);
    });

    test('the lash falloff peaks at the lower lid and fades below', () {
      expect(at(RetouchChannel.lash, -0.5, 0.085), greaterThan(0.9));
      expect(at(RetouchChannel.lash, -0.5, 0.3), 0);
    });

    test('sclera, iris and pupil are separated', () {
      expect(at(RetouchChannel.sclera, -0.67, 0.0), greaterThan(0.8));
      expect(at(RetouchChannel.sclera, 0.33, 0.0), greaterThan(0.8));
      expect(at(RetouchChannel.sclera, -0.44, 0.0), lessThan(0.05));
      expect(at(RetouchChannel.iris, -0.44, 0.0), greaterThan(0.8));
      expect(
        at(RetouchChannel.iris, -0.5, 0.0),
        lessThan(0.1),
        reason: 'pupil',
      );
      expect(at(RetouchChannel.iris, -0.67, 0.0), lessThan(0.05));
    });

    test('mouth opening and lips', () {
      expect(at(RetouchChannel.mouth, 0.0, 1.13), greaterThan(0.8));
      expect(at(RetouchChannel.mouth, 0.0, 1.03), lessThan(0.05));
      expect(at(RetouchChannel.lips, 0.0, 1.03), greaterThan(0.5));
      expect(at(RetouchChannel.lips, 0.0, 1.13), lessThan(0.05));
      expect(at(RetouchChannel.lips, 0.0, 0.9), lessThan(0.05));
    });

    test('blush and wrinkle maps are zero until step 8', () {
      expect(at(RetouchChannel.blush, -0.62, 0.52), 0);
      expect(at(RetouchChannel.wrinkle, 0.0, -0.7), 0);
    });

    test('the teeth cap is the sclera brightness', () {
      final cap = maps.faceInSlot(0)!.teethCapL;
      expect(cap, closeTo(_face.scleraL, 0.02));
    });
  });

  test('maps are deterministic', () {
    final again = computeRetouchMaps(p.image, p.analysis);
    expect(again.regionA, maps.regionA);
    expect(again.regionB, maps.regionB);
    expect(again.b2, maps.b2);
    expect(again.bh, maps.bh);
  });

  group('FaceParsingPlanes', () {
    FaceParsingPlanes planes({required bool hairOnLeftCheek}) {
      const n = 64;
      final skin = Uint8List(n * n)..fillRange(0, n * n, 255);
      final hair = Uint8List(n * n);
      if (hairOnLeftCheek) {
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n ~/ 2; x++) {
            hair[y * n + x] = 255;
          }
        }
      }
      return FaceParsingPlanes(
        faceId: 'a',
        cropX: (256 - 1.3 * 140) / 512,
        cropY: (200 - 1.3 * 140) / 512,
        cropWidth: 2.6 * 140 / 512,
        cropHeight: 3.4 * 140 / 512,
        width: n,
        height: n,
        background: Uint8List(n * n),
        hair: hair,
        bodySkin: Uint8List(n * n),
        faceSkin: skin,
        clothes: Uint8List(n * n),
        accessories: Uint8List(n * n),
      );
    }

    test('planes drive the skin map when present', () {
      final withHair = computeRetouchMaps(
        p.image,
        p.analysis,
        parsing: [planes(hairOnLeftCheek: true)],
      );
      final clean = computeRetouchMaps(
        p.image,
        p.analysis,
        parsing: [planes(hairOnLeftCheek: false)],
      );
      final q = _face.toPx(-0.6, 0.3), r = _face.toPx(0.55, 0.15);
      double skin(RetouchMaps m, ({double x, double y}) s) =>
          regionAt(m, RetouchChannel.skin, s.x.floor(), s.y.floor(), 512, 512);
      expect(skin(clean, q), greaterThan(0.8));
      expect(skin(withHair, q), lessThan(0.05));
      expect(skin(withHair, r), greaterThan(0.8));
    });

    test('rejects planes of the wrong size', () {
      expect(
        () => FaceParsingPlanes(
          faceId: 'a',
          cropX: 0,
          cropY: 0,
          cropWidth: 1,
          cropHeight: 1,
          width: 4,
          height: 4,
          background: Uint8List(16),
          hair: Uint8List(16),
          bodySkin: Uint8List(16),
          faceSkin: Uint8List(15),
          clothes: Uint8List(16),
          accessories: Uint8List(16),
        ),
        throwsArgumentError,
      );
    });

    test('samples bilinearly inside the crop and 0 outside', () {
      final pl = planes(hairOnLeftCheek: false);
      expect(pl.sample(ParsingClass.faceSkin, 0.5, 0.4), 1);
      expect(pl.sample(ParsingClass.faceSkin, 0.01, 0.01), 0);
    });
  });
}
