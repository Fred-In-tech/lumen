import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 384, _h = 384;

PortraitSettings get _teeth => PortraitSettings.empty
    .withGroupValue(FaceGroup.all, PortraitIds.teethBrightness, 100)
    .withGroupValue(FaceGroup.all, PortraitIds.teethDesaturate, 100);

void main() {
  ({RgbaBuffer out, SynthPortrait p, RetouchMaps maps}) whiten(double sclera) {
    final face = SynthFace(
      id: 'a',
      cx: 192,
      cy: 150,
      iod: 110,
      scleraL: sclera,
      teethL: 0.80,
    );
    final p = renderSynthPortrait(_w, _h, [face]);
    final maps = computeRetouchMaps(p.image, p.analysis);
    final out = applyRetouch(
      p.image,
      maps,
      RetouchUniforms.fromSettings(_teeth, p.analysis),
    );
    return (out: out, p: p, maps: maps);
  }

  bool isTooth(RetouchMaps maps, List<double> inL, int i) =>
      regionAt(maps, RetouchChannel.mouth, i % _w, i ~/ _w, _w, _h) > 0.3 &&
      inL[i] > 0.6;

  test('teeth never get brighter than the sclera (§3.6 cap)', () {
    final r = whiten(0.80);
    final cap = r.maps.faceInSlot(0)!.teethCapL;
    expect(cap, closeTo(0.80, 0.02));
    final inLab = labOf(r.p.image), outLab = labOf(r.out);
    var teeth = 0;
    for (var i = 0; i < _w * _h; i++) {
      if (!isTooth(r.maps, inLab.l, i)) continue;
      teeth++;
      final limit = inLab.l[i] > cap ? inLab.l[i] : cap;
      expect(outLab.l[i], lessThanOrEqualTo(limit + 0.004), reason: 'px $i');
    }
    expect(teeth, greaterThan(100));
    final bBefore = meanWhere(
      _w * _h,
      (i) => isTooth(r.maps, inLab.l, i),
      (i) => inLab.b[i],
    );
    final bAfter = meanWhere(
      _w * _h,
      (i) => isTooth(r.maps, inLab.l, i),
      (i) => outLab.b[i],
    );
    expect(
      bAfter,
      lessThan(0.5 * bBefore),
      reason: 'still whitened (less yellow)',
    );
  });

  test('with bright sclera the same sliders do brighten the teeth', () {
    final r = whiten(0.95);
    final inLab = labOf(r.p.image), outLab = labOf(r.out);
    final lift = meanWhere(
      _w * _h,
      (i) => isTooth(r.maps, inLab.l, i),
      (i) => outLab.l[i] - inLab.l[i],
    );
    expect(lift, greaterThan(0.005));
  });

  test('gums, tongue and lips are not whitened', () {
    final r = whiten(0.95);
    final face = r.p.faces.first;
    final tongue = face.toPx(0, kMouthTongueY);
    final lip = face.toPx(0, 1.03);
    final inLab = labOf(r.p.image), outLab = labOf(r.out);
    for (final q in [tongue, lip]) {
      final i = q.y.floor() * _w + q.x.floor();
      expect(outLab.a[i], closeTo(inLab.a[i], 0.004));
    }
  });
}
