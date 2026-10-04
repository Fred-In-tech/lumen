import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// A view whose class probabilities come from [f](channel, u, v) over a
/// [size]² tensor with no letterbox, covering [region].
SegmentationView view(
  PixelRegion region,
  double Function(int c, double u, double v) f, {
  int size = 16,
  Letterbox letterbox = const Letterbox(),
}) {
  final p = Float32List(size * size * SelfieClass.count);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      for (var c = 0; c < SelfieClass.count; c++) {
        p[(y * size + x) * SelfieClass.count + c] = f(
          c,
          (x + 0.5) / size,
          (y + 0.5) / size,
        );
      }
    }
  }
  return SegmentationView(
    probabilities: p,
    width: size,
    height: size,
    channels: SelfieClass.count,
    region: region,
    letterbox: letterbox,
  );
}

const _full = (left: 0, top: 0, width: 200, height: 100);

void main() {
  group('maskRef', () {
    test('file-safe, parseable, one raster per kind family', () {
      final ref = aiMaskRef(AiRaster.people, 'selfie_multiclass_256@1');
      expect(ref, 'people.selfie_multiclass_256-1');
      final parsed = parseAiMaskRef(ref)!;
      expect(parsed.raster, AiRaster.people);
      expect(parsed.model, 'selfie_multiclass_256-1');
      for (final bad in ['../x', 'people', 'nope.m-1', 'people.a/b', '']) {
        expect(parseAiMaskRef(bad), isNull, reason: bad);
      }
      expect(AiRaster.forKind(MaskKind.subject), AiRaster.people);
      expect(AiRaster.forKind(MaskKind.person), AiRaster.people);
      expect(AiRaster.forKind(MaskKind.background), AiRaster.background);
      expect(AiRaster.forKind(MaskKind.faceSkin), AiRaster.faceSkin);
      expect(AiRaster.forKind(MaskKind.sky), isNull);
      expect(AiRaster.forKind(MaskKind.radial), isNull);
    });
  });

  group('multiclassProbabilities', () {
    test('keeps probabilities, softmaxes logits', () {
      final probs = Float32List.fromList([0.7, 0.3, 0.1, 0.9]);
      expect(multiclassProbabilities(probs, 2), probs);
      final logits = Float32List.fromList([2, -1, -3, 4]);
      final p = multiclassProbabilities(logits, 2);
      expect(p[0] + p[1], closeTo(1, 1e-6));
      expect(p[0], greaterThan(p[1]));
      expect(p[3], greaterThan(0.99));
      expect(
        () => multiclassProbabilities(Float32List(3), 2),
        throwsArgumentError,
      );
    });
  });

  group('SegmentationView', () {
    test('samples through the letterbox, never into the padding', () {
      // 200×100 image in a square tensor: content rows 4..11 of 16.
      final v = view(
        _full,
        (c, u, y) => y >= 0.25 && y < 0.75 ? 1 : 0,
        letterbox: const Letterbox(top: 0.25, bottom: 0.25),
      );
      expect(v.sample(0, 100, 50), closeTo(1, 1e-6));
      expect(v.sample(0, 100, 0.5), closeTo(1, 1e-6));
      expect(v.sample(0, 100, 99.5), closeTo(1, 1e-6));
    });

    test('feathered weight inside the region, 0 outside', () {
      final v = view((
        left: 50,
        top: 0,
        width: 100,
        height: 100,
      ), (c, u, w) => 0);
      expect(v.weight(100, 50), 1);
      expect(v.weight(10, 50), 0);
      final edge = v.weight(52, 50); // 2 % in from the left edge
      expect(edge, greaterThan(0));
      expect(edge, lessThan(1));
    });
  });

  group('composeAiMasks', () {
    test('people = 1 − background; planes sum to 255', () {
      // Background on the left half of the image.
      final whole = view(
        _full,
        (c, u, v) => c == SelfieClass.background ? (u < 0.5 ? 1 : 0) : 0,
      );
      final planes = composeAiMasks(
        gridWidth: 40,
        gridHeight: 20,
        sourceWidth: 200,
        sourceHeight: 100,
        whole: whole,
      );
      final people = planes.planes[AiRaster.people]!;
      final bg = planes.planes[AiRaster.background]!;
      expect(bg[10 * 40 + 2], 255);
      expect(people[10 * 40 + 2], 0);
      expect(people[10 * 40 + 37], 255);
      for (var i = 0; i < people.length; i++) {
        expect(people[i] + bg[i], inInclusiveRange(254, 256));
      }
      expect(planes.raster(AiRaster.hair).width, 40);
    });

    test('per-face crops replace the whole pass inside, feathered', () {
      final whole = view(_full, (c, u, v) => 0);
      final face = view((
        left: 80,
        top: 20,
        width: 40,
        height: 40,
      ), (c, u, v) => c == SelfieClass.faceSkin ? 1 : 0);
      final planes = composeAiMasks(
        gridWidth: 200,
        gridHeight: 100,
        sourceWidth: 200,
        sourceHeight: 100,
        whole: whole,
        faces: [face],
      );
      final skin = planes.planes[AiRaster.faceSkin]!;
      expect(skin[40 * 200 + 100], 255); // crop centre
      expect(skin[40 * 200 + 20], 0); // far outside
      final rim = skin[40 * 200 + 81]; // just inside the crop edge
      expect(rim, greaterThan(0));
      expect(rim, lessThan(255));
    });

    test('a crop that loses the person the whole pass sees is dropped', () {
      // Whole pass: a person with face skin everywhere.
      final whole = view(_full, (c, u, v) => c == SelfieClass.faceSkin ? 1 : 0);
      PixelRegion crop() => (left: 80, top: 20, width: 40, height: 40);
      final lost = view(
        crop(),
        (c, u, v) => c == SelfieClass.background ? 1 : 0,
      );
      final agrees = view(crop(), (c, u, v) => c == SelfieClass.hair ? 1 : 0);
      expect(personAgreement(whole, lost), (0.0, 1.0));
      AiMaskPlanes compose(SegmentationView f) => composeAiMasks(
        gridWidth: 200,
        gridHeight: 100,
        sourceWidth: 200,
        sourceHeight: 100,
        whole: whole,
        faces: [f],
      );
      final dropped = compose(lost);
      expect(dropped.faceCropsUsed, 0);
      expect(dropped.planes[AiRaster.faceSkin]![40 * 200 + 100], 255);
      final kept = compose(agrees);
      expect(kept.faceCropsUsed, 1);
      expect(kept.planes[AiRaster.hair]![40 * 200 + 100], 255);
    });

    test('guided refinement sharpens a coarse edge onto the photo edge', () {
      // Coarse 4×4 model output: background on the left, soft in between.
      final whole = view(
        _full,
        (c, u, v) => c == SelfieClass.background ? (u < 0.5 ? 1.0 : 0.0) : 0,
        size: 4,
      );
      // The photo has a sharp edge at x = 100 (source) = column 50 (grid).
      final guide = Float32List.fromList([
        for (var y = 0; y < 50; y++)
          for (var x = 0; x < 100; x++) x < 50 ? 0.1 : 0.9,
      ]);
      double err(Float32List? g) {
        final p = composeAiMasks(
          gridWidth: 100,
          gridHeight: 50,
          sourceWidth: 200,
          sourceHeight: 100,
          whole: whole,
          guide: g,
          refine: const GuidedFilterParams(radius: 16, eps: 1e-4),
        ).planes[AiRaster.people]!;
        var e = 0.0;
        for (var i = 0; i < p.length; i++) {
          e += (p[i] / 255 - (i % 100 < 50 ? 0 : 1)).abs();
        }
        return e / p.length;
      }

      expect(err(guide), lessThan(err(null) * 0.6));
    });
  });
}
