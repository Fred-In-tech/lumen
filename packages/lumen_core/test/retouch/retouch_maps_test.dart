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
      expect([maps.width, maps.height], [576, 420]);
      for (final t in [maps.b1, maps.b2, maps.b3]) {
        expect(t, hasLength(n));
      }
      for (final t in [maps.bh, maps.regionA, maps.regionB]) {
        expect(t, hasLength(2 * n));
      }
      for (final t in [
        maps.b1,
        maps.b2,
        maps.b3,
        maps.bh,
        maps.regionA,
        maps.regionB,
      ]) {
        for (var i = 3; i < t.length; i += 4) {
          if (t[i] != 255) fail('alpha at $i is ${t[i]}');
        }
      }
    });

    test('face ids are slot + 1 and the spare channel stays 0', () {
      final ids = <int>{};
      final w = maps.width;
      for (var y = 0; y < maps.height; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * 2 * w + w + x) * 4;
          ids.add(maps.regionB[o]);
          expect(maps.regionB[o + 2], 0);
        }
      }
      expect(ids, {0, 1, 2});
      expect(maps.faces.map((f) => f.slot), [0, 1]);
      expect(maps.faces.map((f) => f.faceId), ['a', 'b']);
    });

    test('each face owns its own centre', () {
      for (final (f, id) in [(_a, 1), (_b, 2)]) {
        for (final (x, y) in const [(0.5, 0.4), (-0.5, 0.4), (0.0, 1.3)]) {
          final q = f.toPx(x, y);
          expect(maps.nearest(RetouchChannel.faceId, q.x / 576, q.y / 420), id);
        }
      }
    });

    test('packInfo carries the size and the teeth caps', () {
      final info = maps.packInfo();
      expect(info, hasLength(4 + 4 * kMaxRetouchFaces));
      expect(info.sublist(0, 3), [576, 420, 2]);
      expect(info[4], closeTo(_a.scleraL, 0.02));
      expect(info[5], 1);
      expect(info[4 + 4 * 2 + 1], 0, reason: 'slot 2 has no maps');
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

  group('analysis grid Rres (§3.0)', () {
    test('aims for an IOD of 160 within 1024–2048, never above the source', () {
      expect(retouchMapLongEdge(4000, 400), 1600);
      expect(retouchMapLongEdge(4000, 100), kRetouchMaxLongEdge);
      expect(retouchMapLongEdge(6000, 3000), kRetouchMinLongEdge);
      expect(retouchMapLongEdge(800, 50), 800);
    });

    test('faces under 24 px IOD get no maps', () {
      final tiny = renderSynthPortrait(256, 256, [
        const SynthFace(id: 't', cx: 128, cy: 110, iod: 20),
      ]);
      expect(computeRetouchMaps(tiny.image, tiny.analysis).hasFaces, isFalse);
    });

    test('maps on a coarser grid are sampled in source uv', () {
      final coarse = computeRetouchMaps(p.image, p.analysis, longEdge: 288);
      expect([coarse.width, coarse.height], [288, 210]);
      final q = _a.toPx(0.55, 0.15);
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
  });

  test('computeRetouchMaps is isolate-safe and deterministic', () async {
    final image = p.image, analysis = p.analysis;
    final remote = await Isolate.run(() => computeRetouchMaps(image, analysis));
    expect(remote.regionA, maps.regionA);
    expect(remote.regionB, maps.regionB);
    expect(remote.b1, maps.b1);
    expect(remote.bh, maps.bh);
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
            .withGroupValue(FaceGroup.male, PortraitIds.skinSoftening, 25),
      );
      final ra = blotchContrast(out, _a) / blotchContrast(p.image, _a);
      final rb = blotchContrast(out, _b) / blotchContrast(p.image, _b);
      expect(ra, lessThan(0.6));
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
        final slot = maps.nearest(
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
      expect(r, lessThan(0.6));
    });
  });
}
