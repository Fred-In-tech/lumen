import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;
const _face = SynthFace(
  id: 'a',
  cx: 256,
  cy: 200,
  iod: 140,
  clippedShine: true,
);

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
  });

  ({Float64List l, Float64List a, Float64List b}) run(double shine) => labOf(
    applyRetouch(
      p.image,
      maps,
      RetouchUniforms.fromSettings(
        PortraitSettings.empty.withGroupValue(
          FaceGroup.all,
          PortraitIds.skinShine,
          shine,
        ),
        p.analysis,
      ),
    ),
  );

  final c = _face.toPx(kCoreX, kCoreY);
  final core = 0.02 * _face.iod;
  // The sheen just outside the filled hole (the core is filled from it).
  final ringIn = 0.07 * _face.iod, ringOut = 0.09 * _face.iod;

  double chroma(
    ({Float64List l, Float64List a, Float64List b}) lab,
    bool ring,
  ) {
    final r0 = ring ? ringIn : 0.0, r1 = ring ? ringOut : core;
    final a = ringMean(lab.a, _w, c.x, c.y, r0, r1);
    final b = ringMean(lab.b, _w, c.x, c.y, r0, r1);
    return math.sqrt(a * a + b * b);
  }

  test('the fixture core is clipped and marked as a kind-3 spot', () {
    final i = (c.y.floor() * _w + c.x.floor()) * 4;
    expect(p.image.data[i], 255);
    expect(
      maps.nearest(RetouchChannel.spotCode, c.x / _w, c.y / _h),
      kShineCoreCode,
    );
    expect(spotSelection(kShineCoreCode, 1, 1, 1, 0), 0);
    expect(spotSelection(kShineCoreCode, 0, 0, 0, 0.7), 0.7);
  });

  test('a face without clipped highlights has no core codes', () {
    final plain = renderSynthPortrait(_w, _h, [
      const SynthFace(id: 'a', cx: 256, cy: 200, iod: 140),
    ]);
    final m = computeRetouchMaps(plain.image, plain.analysis);
    final w = m.width;
    for (var y = 0; y < m.height; y++) {
      for (var x = 0; x < w; x++) {
        expect(m.regionB[(y * 2 * w + w + x) * 4 + 1], isNot(kShineCoreCode));
      }
    }
  });

  test('below 50 % the clipped core stays a grey blob', () {
    final out = run(40);
    expect(chroma(out, false) / chroma(out, true), lessThan(0.3));
    final lCore = discMean(out.l, _w, c.x, c.y, core);
    expect(
      lCore - ringMean(out.l, _w, c.x, c.y, ringIn, ringOut),
      greaterThan(0.1),
    );
  });

  test('above 50 % the core blends into the sheen around it', () {
    final out = run(100);
    expect(chroma(out, false) / chroma(out, true), greaterThan(0.85));
    final lCore = discMean(out.l, _w, c.x, c.y, core);
    final lRing = ringMean(out.l, _w, c.x, c.y, ringIn, ringOut);
    expect((lCore - lRing).abs(), lessThan(0.02));
  });

  test('the fill starts exactly at 50 % (continuous)', () {
    final a = run(49), b = run(50);
    final i = c.y.floor() * _w + c.x.floor();
    expect(b.l[i], closeTo(a.l[i], 0.01));
  });
}
