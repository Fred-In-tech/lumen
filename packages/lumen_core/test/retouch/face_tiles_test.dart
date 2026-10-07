import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_portrait.dart';

const _w = 560, _h = 380;

/// Two faces whose work rects overlap, the right one smaller.
const _a = SynthFace(id: 'a', cx: 200, cy: 150, iod: 90);
const _b = SynthFace(id: 'b', cx: 330, cy: 170, iod: 60);

void main() {
  late SynthPortrait p, full;
  late List<FaceTileImage> tiles;
  late RetouchMaps mixed;

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_a, _b]);
    // A 2× "original": face a gets its tile from it, face b from the decode.
    full = renderSynthPortrait(2 * _w, 2 * _h, [
      const SynthFace(id: 'a', cx: 400, cy: 300, iod: 180),
      const SynthFace(id: 'b', cx: 660, cy: 340, iod: 120),
    ]);
    final plans = planFaceTiles(p.analysis, 2 * _w, 2 * _h);
    tiles = [FaceTileImage(plans[0], resampleTile(full.image, plans[0]))];
    mixed = computeRetouchMaps(p.image, p.analysis, tiles: tiles);
  });

  test('faces keep their own scale in one atlas', () {
    expect(mixed.faces.map((f) => f.iod), [closeTo(180, 1), closeTo(60, 1)]);
    final ta = mixed.transformOf(mixed.faces[0]);
    final tb = mixed.transformOf(mixed.faces[1]);
    expect(ta.sx, 2 * _w);
    expect(tb.sx, _w);
    expect(mixed.faces[0].rect.intersect(mixed.faces[1].rect).isEmpty, isTrue);
  });

  test('overlaps are owned in source space: nearest size-normalized '
      'centre', () {
    // Nose centres in source px, IOD in source px.
    final ca = _a.toPx(0, 0.45), cb = _b.toPx(0, 0.45);
    var checked = 0;
    for (var x = 230; x < 320; x += 3) {
      for (var y = 120; y < 230; y += 7) {
        final u = (x + 0.5) / _w, v = (y + 0.5) / _h;
        final id = mixed.sourceNearest(RetouchChannel.faceId, u, v);
        if (id == 0) continue;
        final da = math.sqrt(
          math.pow(x + 0.5 - ca.x, 2) + math.pow(y + 0.5 - ca.y, 2),
        );
        final db = math.sqrt(
          math.pow(x + 0.5 - cb.x, 2) + math.pow(y + 0.5 - cb.y, 2),
        );
        // Away from the boundary (texel rounding), the rule decides.
        if ((da / _a.iod - db / _b.iod).abs() < 0.05) continue;
        expect(id, da / _a.iod < db / _b.iod ? 1 : 2, reason: '($x, $y)');
        checked++;
      }
    }
    expect(checked, greaterThan(20));
  });

  test('locate finds nothing outside every tile', () {
    final out = [0.0, 0.0];
    expect(mixed.locate(0.995, 0.995, out), -1);
    expect(mixed.sourceNearest(RetouchChannel.faceId, 0.995, 0.995), 0);
    expect(mixed.sourceRegion(RetouchChannel.skin, 0.995, 0.995), 0);
  });

  test('the CPU pass only touches the faces and works at any size', () {
    final u = RetouchUniforms.fromSettings(
      PortraitSettings.empty.withGroupValue(
        FaceGroup.all,
        PortraitIds.skinSoftening,
        100,
      ),
      p.analysis,
    );
    for (final img in [p.image, full.image]) {
      final out = applyRetouch(img, mixed, u);
      var changed = 0, outside = 0;
      for (var i = 0; i < img.data.length; i += 4) {
        if (out.data[i] == img.data[i] &&
            out.data[i + 1] == img.data[i + 1] &&
            out.data[i + 2] == img.data[i + 2]) {
          continue;
        }
        changed++;
        final x = (i ~/ 4) % img.width, y = (i ~/ 4) ~/ img.width;
        final id = mixed.sourceNearest(
          RetouchChannel.faceId,
          (x + 0.5) / img.width,
          (y + 0.5) / img.height,
        );
        if (id == 0) outside++;
      }
      expect(changed, greaterThan(500));
      expect(outside, 0);
    }
  });

  test('the pen paints the same source point on a 2× tile', () {
    final q = _a.toPx(-0.4, 0.4);
    final u = q.x / _w, v = q.y / _h;
    final erase = BrushStroke(
      points: [(u, v)],
      radius: 0.03,
      hardness: 1,
      erase: true,
    );
    final before = mixed.sourceRegion(RetouchChannel.skin, u, v);
    final pen = applySkinPen(mixed, [erase]);
    expect(before, greaterThan(200));
    expect(pen.sourceRegion(RetouchChannel.skin, u, v), lessThan(5));
    // Face b's skin is untouched.
    final r = _b.toPx(0.4, 0.6);
    expect(
      pen.sourceRegion(RetouchChannel.skin, r.x / _w, r.y / _h),
      mixed.sourceRegion(RetouchChannel.skin, r.x / _w, r.y / _h),
    );
  });

  test('Auto Retouch measures through the tile transforms', () {
    final needs = measureRetouchNeeds(mixed, p.image, p.analysis);
    expect(needs.faces, hasLength(2));
    expect(needs.faces.first.iod, closeTo(180, 1));
  });

  group('parsing planes', () {
    const plan = FaceTilePlan(
      slot: 0,
      faceId: 'a',
      gridW: 100,
      gridH: 50,
      window: MapRect(10, 5, 40, 20),
    );

    test('fromTile keeps only the tile inside the letterbox', () {
      // 8×8 tensor, tile 40×20 → image rows 2..5 (pad 0.25 each side).
      const w = 8, h = 8, ch = 6;
      final probs = Float32List(w * h * ch);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * ch;
          probs[o + (y < 2 || y >= 6 ? 0 : (x < 4 ? 1 : 3))] = 1;
        }
      }
      final pl = FaceParsingPlanes.fromTile(
        plan,
        probs,
        width: w,
        height: h,
        channels: ch,
        letterbox: const Letterbox(top: 0.25, bottom: 0.25),
      );
      expect([pl.width, pl.height], [8, 4]);
      expect([pl.cropX, pl.cropY], [0.1, 0.1]);
      expect(pl.cropWidth, closeTo(0.4, 1e-12));
      expect(pl.cropHeight, closeTo(0.4, 1e-12));
      expect(pl.hair.sublist(0, 4), [255, 255, 255, 255]);
      expect(pl.faceSkin.sublist(4, 8), [255, 255, 255, 255]);
      expect(pl.background.every((v) => v == 0), isTrue);
      // Bilinear sample in source uv: left half hair, right half skin.
      expect(pl.sample(ParsingClass.hair, 0.12, 0.3), closeTo(1, 1e-9));
      expect(pl.sample(ParsingClass.faceSkin, 0.48, 0.3), closeTo(1, 1e-9));
      expect(pl.sample(ParsingClass.faceSkin, 0.05, 0.3), 0);
      expect(
        () => FaceParsingPlanes.fromTile(
          plan,
          Float32List(5),
          width: w,
          height: h,
          channels: ch,
          letterbox: const Letterbox(),
        ),
        throwsArgumentError,
      );
      expect(
        () => FaceParsingPlanes.fromTile(
          plan,
          probs,
          width: w,
          height: h,
          channels: ch,
          letterbox: const Letterbox(top: 0.5, bottom: 0.5),
        ),
        throwsArgumentError,
      );
    });

    test('the cache codec round-trips and rejects anything else', () {
      Uint8List plane(int seed) => Uint8List.fromList([
        for (var i = 0; i < 6; i++) (i * 37 + seed) & 255,
      ]);
      final a = FaceParsingPlanes(
        faceId: 'fäce-1',
        cropX: 0.1,
        cropY: 0.2,
        cropWidth: 0.3,
        cropHeight: 0.4,
        width: 3,
        height: 2,
        background: plane(1),
        hair: plane(2),
        bodySkin: plane(3),
        faceSkin: plane(4),
        clothes: plane(5),
        accessories: plane(6),
      );
      final bytes = encodeParsingPlanes([a, a]);
      final back = decodeParsingPlanes(bytes)!;
      expect(back, hasLength(2));
      expect(back.first.faceId, 'fäce-1');
      expect(
        [back[1].cropX, back[1].cropY, back[1].cropWidth, back[1].cropHeight],
        [0.1, 0.2, 0.3, 0.4],
      );
      for (var c = 0; c < 6; c++) {
        expect(back.first.planes[c], a.planes[c]);
      }
      expect(decodeParsingPlanes(encodeParsingPlanes(const [])), isEmpty);
      expect(decodeParsingPlanes(bytes.sublist(0, bytes.length - 1)), isNull);
      expect(decodeParsingPlanes(Uint8List.fromList([...bytes, 0])), isNull);
      expect(decodeParsingPlanes(Uint8List(3)), isNull);
      final wrongMagic = Uint8List.fromList(bytes)..[0] = 0x58;
      expect(decodeParsingPlanes(wrongMagic), isNull);
      final wrongVersion = Uint8List.fromList(bytes)..[4] = 9;
      expect(decodeParsingPlanes(wrongVersion), isNull);
      final badUtf8 = Uint8List.fromList(bytes)..[16] = 0xff;
      expect(decodeParsingPlanes(badUtf8), isNull);
    });
  });
}
