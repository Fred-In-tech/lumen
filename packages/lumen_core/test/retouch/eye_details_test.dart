import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_landmarks.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;
const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140, veins: true);

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
  });

  RgbaBuffer run(String id, double v) => applyRetouch(
    p.image,
    maps,
    RetouchUniforms.fromSettings(
      PortraitSettings.empty.withGroupValue(FaceGroup.all, id, v),
      p.analysis,
    ),
  );

  bool onVein(int i) {
    final q = _face.toLocal(i % _w + 0.5, i ~/ _w + 0.5);
    final ex = q.x < 0 ? -0.5 : 0.5;
    return q.y.abs() < 0.06 &&
        (q.x - ex).abs() < kEyeOuterX - 0.55 &&
        isVein(q.x - ex, q.y) &&
        regionAt(maps, RetouchChannel.sclera, i % _w, i ~/ _w, _w, _h) > 0.6;
  }

  test('red veins are softened by up to half, never erased', () {
    final before = labOf(p.image), after = labOf(run(PortraitIds.redVein, 100));
    final a0 = meanWhere(_w * _h, onVein, (i) => before.a[i]);
    final a1 = meanWhere(_w * _h, onVein, (i) => after.a[i]);
    expect(a0, greaterThan(0.04));
    expect(a1, inInclusiveRange(0.5 * a0, 0.85 * a0));
  });

  test('eye bags flatten the under-eye shading toward the cheek', () {
    final before = labOf(p.image).l,
        after = labOf(run(PortraitIds.eyeBags, 100)).l;
    bool under(int i) =>
        regionAt(maps, RetouchChannel.underEye, i % _w, i ~/ _w, _w, _h) >
            0.6 &&
        regionAt(maps, RetouchChannel.lash, i % _w, i ~/ _w, _w, _h) < 0.1;
    final c = _face.toPx(-0.5, 0.42);
    final cheek0 = discMean(before, _w, c.x, c.y, 8);
    final gap0 = cheek0 - meanWhere(_w * _h, under, (i) => before[i]);
    final gap1 =
        discMean(after, _w, c.x, c.y, 8) -
        meanWhere(_w * _h, under, (i) => after[i]);
    expect(gap1, lessThan(0.8 * gap0));
  });
}
