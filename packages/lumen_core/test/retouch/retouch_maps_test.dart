import 'dart:isolate';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _a = SynthFace(
  id: 'a',
  cx: 150,
  cy: 150,
  iod: 100,
  group: FaceGroup.female,
);
const _b = SynthFace(id: 'b', cx: 420, cy: 160, iod: 90, group: FaceGroup.male);

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;

  setUpAll(() {
    p = renderSynthPortrait(576, 420, [_a, _b]);
    maps = computeRetouchMaps(p.image, p.analysis);
  });

  group('layout', () {
    test('textures have the documented sizes and A = 255 everywhere', () {
      final n = maps.width * maps.height * 4;
      // One atlas of per-face tiles (IOD 100 / 90 < 224: native size).
      expect(maps.width, lessThanOrEqualTo(kAtlasShelfPx));
      expect(maps.faces.map((f) => f.iod), [
        closeTo(100, 0.5),
        closeTo(90, 0.5),
      ]);
      expect(maps.low, hasLength(n));
      for (final t in [
        maps.deltaA,
        maps.deltaB,
        maps.deltaC,
        maps.regionA,
        maps.regionB,
      ]) {
        expect(t, hasLength(2 * n));
      }
      for (final t in [
        maps.low,
        maps.deltaA,
        maps.deltaB,
        maps.deltaC,
        maps.regionA,
        maps.regionB,
      ]) {
        for (var i = 3; i < t.length; i += 4) {
          if (t[i] != 255) fail('alpha at $i is ${t[i]}');
        }
      }
    });

    test('face ids are slot + 1; zone codes only where a wrinkle is', () {
      final ids = <int>{}, zones = <int>{};
      final w = maps.width;
      for (var y = 0; y < maps.height; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * 2 * w + w + x) * 4;
          ids.add(maps.regionB[o]);
          final zone = maps.regionB[o + 2];
          zones.add(zone);
          if (zone != 0) {
            expect(maps.regionB[(y * 2 * w + x) * 4 + 2], greaterThan(0));
          }
          expect(zone, lessThanOrEqualTo(kZoneCodeCrowsFeet));
        }
      }
      expect(zones.any((z) => z >= 1 && z < kZoneCodeSmile), isTrue);
      expect(
        zones.any((z) => z >= kZoneCodeSmile && z < kZoneCodeCrowsFeet),
        isTrue,
      );
      expect(zones, contains(kZoneCodeCrowsFeet));
      expect(ids, {0, 1, 2});
      expect(maps.faces.map((f) => f.slot), [0, 1]);
      expect(maps.faces.map((f) => f.faceId), ['a', 'b']);
    });

    test('each face owns its own centre', () {
      for (final (f, id) in [(_a, 1), (_b, 2)]) {
        for (final (x, y) in const [(0.5, 0.4), (-0.5, 0.4), (0.0, 1.3)]) {
          final q = f.toPx(x, y);
          expect(
            maps.sourceNearest(RetouchChannel.faceId, q.x / 576, q.y / 420),
            id,
          );
        }
      }
    });

    test('packInfo carries size, teeth caps, makeup, eyes and backdrop', () {
      final info = maps.packInfo();
      expect(info, hasLength(kRetouchInfoFloats));
      expect(kRetouchInfoFloats, 108);
      expect(info.sublist(0, 3), [maps.width, maps.height, 2]);
      final a = maps.faceInSlot(0)!;
      expect(info[4], closeTo(_a.scleraL, 0.02));
      expect(info[5], 1);
      expect(info[6], closeTo(a.iod, 1e-3));
      expect(info[7], closeTo(a.lipGlossL, 1e-6));
      expect(info[8], closeTo(a.lipChromaGain, 1e-6));
      expect(info[9], closeTo(a.lipShiftL, 1e-6));
      expect(info[10], closeTo(a.blushA, 1e-6));
      expect(info[11], closeTo(a.blushB, 1e-6));
      // Iris centres in map px: image px through the face's transform.
      final r = _a.toPx(-0.5, 0), l = _a.toPx(0.5, 0);
      final t = maps.transformOf(a);
      expect(t.sx, 576);
      expect(t.sy, 420);
      expect(info[12], closeTo(r.x + t.tx, 0.01));
      expect(info[13], closeTo(r.y + t.ty, 0.01));
      expect(info[14], closeTo(l.x + t.tx, 0.01));
      expect(info[15], closeTo(l.y + t.ty, 0.01));
      expect(info[16 + 1], 1, reason: 'slot 1 has maps');
      expect(info[4 + 12 * 2 + 1], 0, reason: 'slot 2 has no maps');
      expect(info[4 + 12 * 2 + 4], 1, reason: 'neutral lip gain');
      // Backdrop not requested: 1×1, not ready.
      expect(info.sublist(100, 103), [1, 1, 0]);
    });

    test('no faces gives 1×1 neutral maps and a no-op apply', () {
      final empty = computeRetouchMaps(
        p.image,
        const FaceAnalysis(
          imageWidth: 576,
          imageHeight: 420,
          modelVersion: 'x',
        ),
      );
      expect(empty.hasFaces, isFalse);
      expect([empty.width, empty.height], [1, 1]);
      final u = RetouchUniforms.fromSettings(
        PortraitSettings.empty.withGroupValue(
          FaceGroup.all,
          PortraitIds.skinSoftening,
          50,
        ),
        p.analysis,
      );
      expect(identical(applyRetouch(p.image, empty, u), p.image), isTrue);
    });
  });

  group('per-face tiles', () {
    test('aim for an IOD of 224, never above the source', () {
      final big = renderSynthPortrait(900, 700, [
        const SynthFace(id: 'big', cx: 450, cy: 330, iod: 300),
      ]);
      final plans = planFaceTiles(big.analysis, 900, 700);
      expect(plans, hasLength(1));
      expect(plans.single.gridW / 900, closeTo(224 / 300, 0.01));
      final small = planFaceTiles(p.analysis, 576, 420);
      expect(small.map((t) => (t.gridW, t.gridH)), [(576, 420), (576, 420)]);
      // The tile covers the work rect and reaches below the chin.
      final f = FaceFrame.tryCreate(p.analysis.faces[0], 0, 576, 420)!;
      final w = small.first.window;
      expect(w.x0, lessThanOrEqualTo(f.rect.x0));
      expect(w.x1, greaterThanOrEqualTo(f.rect.x1));
      expect(w.y1, greaterThan(f.rect.y1));
    });

    test('many faces share one pixel budget', () {
      final plans = planFaceTiles(p.analysis, 576, 420, budgetPx: 20000);
      final area = plans.fold(0, (a, t) => a + t.width * t.height);
      expect(area, lessThanOrEqualTo(20000 * 1.1));
      expect(plans.first.gridW, lessThan(576));
      // One shared factor: both faces keep their relative scale.
      expect(plans[0].gridW, plans[1].gridW);
    });

    test('atlas packing keeps tiles apart and inside', () {
      final a = packAtlas([(w: 10, h: 20), (w: 4000, h: 5), (w: 30, h: 8)]);
      final r = [
        for (var i = 0; i < 3; i++)
          MapRect(
            a.origins[i].x,
            a.origins[i].y,
            [10, 4000, 30][i],
            [20, 5, 8][i],
          ),
      ];
      for (var i = 0; i < 3; i++) {
        expect(r[i].x0, greaterThanOrEqualTo(kAtlasGutterPx));
        expect(r[i].x1, lessThanOrEqualTo(a.width - kAtlasGutterPx));
        expect(r[i].y1, lessThanOrEqualTo(a.height - kAtlasGutterPx));
        for (var j = i + 1; j < 3; j++) {
          expect(r[i].intersect(r[j]).isEmpty, isTrue);
        }
      }
    });

    test('faces under 24 px IOD get no maps', () {
      final tiny = renderSynthPortrait(256, 256, [
        const SynthFace(id: 't', cx: 128, cy: 110, iod: 20),
      ]);
      expect(computeRetouchMaps(tiny.image, tiny.analysis).hasFaces, isFalse);
    });

    test('coarser tiles are still sampled in source uv', () {
      final coarse = computeRetouchMaps(p.image, p.analysis, targetIod: 50);
      expect(coarse.faces.first.iod, closeTo(50, 1));
      final q = _a.toPx(0.55, 0.24);
      double skin(RetouchMaps m) =>
          regionAt(m, RetouchChannel.skin, q.x.floor(), q.y.floor(), 576, 420);
      expect(skin(coarse), greaterThan(0.8));
      final out = applyRetouch(
        p.image,
        coarse,
        RetouchUniforms.fromSettings(
          PortraitSettings.empty.withGroupValue(
            FaceGroup.all,
            PortraitIds.skinSoftening,
            100,
          ),
          p.analysis,
        ),
      );
      expect(out.data, isNot(p.image.data));
    });

    test('supplied full-resolution tiles set the analysed IOD', () {
      // The "original" is twice the decode: the tiles come from it.
      final full = renderSynthPortrait(1152, 840, [
        const SynthFace(
          id: 'a',
          cx: 300,
          cy: 300,
          iod: 200,
          group: FaceGroup.female,
        ),
        const SynthFace(id: 'b', cx: 840, cy: 320, iod: 180),
      ]);
      final plans = planFaceTiles(p.analysis, 1152, 840);
      final tiles = [
        for (final t in plans) FaceTileImage(t, resampleTile(full.image, t)),
      ];
      final hi = computeRetouchMaps(p.image, p.analysis, tiles: tiles);
      expect(hi.faces.map((f) => f.iod), [closeTo(200, 1), closeTo(180, 1)]);
      // A tile whose face id does not match is ignored (decode fallback).
      final wrong = FaceTileImage(
        FaceTilePlan(
          slot: 0,
          faceId: 'zz',
          gridW: plans[0].gridW,
          gridH: plans[0].gridH,
          window: plans[0].window,
        ),
        tiles[0].pixels,
      );
      final lo = computeRetouchMaps(p.image, p.analysis, tiles: [wrong]);
      expect(lo.faces.first.iod, closeTo(100, 1));
      expect(
        () => FaceTileImage(plans[0], RgbaBuffer(3, 3)),
        throwsArgumentError,
      );
      // The same face is found at the same source uv in both.
      final q = _a.toPx(0, 0.4);
      expect(hi.sourceNearest(RetouchChannel.faceId, q.x / 576, q.y / 420), 1);
      expect(lo.sourceNearest(RetouchChannel.faceId, q.x / 576, q.y / 420), 1);
    });
  });

  test('computeRetouchMaps is isolate-safe and deterministic', () async {
    final image = p.image, analysis = p.analysis;
    final remote = await Isolate.run(() => computeRetouchMaps(image, analysis));
    expect(remote.regionA, maps.regionA);
    expect(remote.regionB, maps.regionB);
    expect(remote.low, maps.low);
    expect(remote.deltaA, maps.deltaA);
    expect(remote.deltaB, maps.deltaB);
    expect(remote.deltaC, maps.deltaC);
    expect(remote.blemishes.map((b) => b.id), maps.blemishes.map((b) => b.id));
  });

  group('per-face strengths from the uniform table', () {
    double blotchContrast(RgbaBuffer img, SynthFace f) {
      final l = labOf(img).l;
      var sum = 0.0;
      for (final b in kBlotches.take(40)) {
        final c = f.toPx(b.x, b.y);
        sum +=
            (discMean(l, img.width, c.x, c.y, 0.012 * f.iod) -
                    ringMean(
                      l,
                      img.width,
                      c.x,
                      c.y,
                      0.06 * f.iod,
                      0.08 * f.iod,
                    ))
                .abs();
      }
      return sum;
    }

    RgbaBuffer run(PortraitSettings s) => applyRetouch(
      p.image,
      maps,
      RetouchUniforms.fromSettings(s, p.analysis),
    );

    test('two faces in different groups get different strengths', () {
      final out = run(
        PortraitSettings.empty
            .withGroupValue(FaceGroup.female, PortraitIds.skinSoftening, 100)
            .withGroupValue(FaceGroup.male, PortraitIds.skinSoftening, 40),
      );
      final ra = blotchContrast(out, _a) / blotchContrast(p.image, _a);
      final rb = blotchContrast(out, _b) / blotchContrast(p.image, _b);
      expect(ra, lessThan(0.7));
      expect(rb, greaterThan(ra + 0.15));
      expect(rb, lessThan(0.97));
    });

    test('a face left at its defaults stays bit-exact', () {
      final out = run(
        PortraitSettings.empty.withGroupValue(
          FaceGroup.female,
          PortraitIds.skinSoftening,
          100,
        ),
      );
      final w = p.image.width;
      var changedA = 0;
      for (var i = 0; i < w * p.image.height; i++) {
        final slot = maps.sourceNearest(
          RetouchChannel.faceId,
          (i % w + 0.5) / w,
          (i ~/ w + 0.5) / p.image.height,
        );
        final o = i * 4;
        final same =
            out.data[o] == p.image.data[o] &&
            out.data[o + 1] == p.image.data[o + 1] &&
            out.data[o + 2] == p.image.data[o + 2];
        if (slot == 2) expect(same, isTrue);
        if (slot == 1 && !same) changedA++;
      }
      expect(changedA, greaterThan(5000));
    });

    test('an individual override beats the group', () {
      final withPerson = renderSynthPortrait(576, 420, [
        _a,
        const SynthFace(
          id: 'b',
          cx: 420,
          cy: 160,
          iod: 90,
          group: FaceGroup.male,
          personId: 'p1',
        ),
      ]);
      final s = PortraitSettings.empty
          .withGroupValue(FaceGroup.male, PortraitIds.skinSoftening, 0)
          .withIndividualValue('p1', PortraitIds.skinSoftening, 100);
      final u = RetouchUniforms.fromSettings(s, withPerson.analysis);
      expect(u.faces[1].smooth, 1);
      final out = applyRetouch(withPerson.image, maps, u);
      final r = blotchContrast(out, _b) / blotchContrast(withPerson.image, _b);
      expect(r, lessThan(0.75));
    });
  });
}
