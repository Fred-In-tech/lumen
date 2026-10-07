import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_core/src/retouch/face_ids.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _n = 512;
const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140, penPatches: true);

/// A horizontal stroke across local (x0..x1, y) with a radius in IOD.
BrushStroke _stroke(
  double x0,
  double x1,
  double y,
  double radiusIod, {
  bool erase = false,
  double hardness = 0.8,
  double flow = 1,
}) {
  final a = _face.toPx(x0, y), b = _face.toPx(x1, y);
  return BrushStroke(
    points: [(a.x / _n, a.y / _n), (b.x / _n, b.y / _n)],
    radius: radiusIod * _face.iod / _n,
    hardness: hardness,
    flow: flow,
    erase: erase,
  );
}

final _eraseStubble = _stroke(
  kStubbleX - kStubbleRx,
  kStubbleX + kStubbleRx,
  kStubbleY,
  kStubbleRy + 0.04,
  erase: true,
);
final _paintTint = _stroke(kTintX - 0.05, kTintX + 0.05, kTintY, kTintR + 0.03);

void main() {
  late SynthPortrait p;
  late RetouchMaps base;

  setUpAll(() {
    p = renderSynthPortrait(_n, _n, [_face]);
    base = computeRetouchMaps(p.image, p.analysis);
  });

  RgbaBuffer smooth(RetouchMaps m, [Map<String, double> extra = const {}]) {
    var s = PortraitSettings.empty.withGroupValue(
      FaceGroup.all,
      PortraitIds.skinSoftening,
      100,
    );
    for (final e in extra.entries) {
      s = s.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    return applyRetouch(
      p.image,
      m,
      RetouchUniforms.fromSettings(s, p.analysis),
    );
  }

  double skinAt(RetouchMaps m, double x, double y) {
    final q = _face.toPx(x, y);
    return regionAt(m, RetouchChannel.skin, q.x.floor(), q.y.floor(), _n, _n);
  }

  bool inStubble(int x, int y, [double scale = 0.85]) {
    final q = _face.toLocal(x + 0.5, y + 0.5);
    final sx = (q.x - kStubbleX) / (kStubbleRx * scale);
    final sy = (q.y - kStubbleY) / (kStubbleRy * scale);
    return sx * sx + sy * sy <= 1;
  }

  test('fixtures: the AI calls the stubble skin and misses the tint', () {
    expect(skinAt(base, kStubbleX, kStubbleY), greaterThan(0.8));
    expect(skinAt(base, kTintX, kTintY), lessThan(0.1));
  });

  test('an erase stroke keeps the stubble untouched at Smooth 100', () {
    final out0 = smooth(base);
    var changed = 0, total = 0;
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        if (!inStubble(x, y)) continue;
        total++;
        final o = (y * _n + x) * 4;
        if (out0.data[o] != p.image.data[o]) changed++;
      }
    }
    expect(changed, greaterThan(total ~/ 2), reason: 'smoothing reaches it');
    final pen = applySkinPen(base, [_eraseStubble]);
    expect(skinAt(pen, kStubbleX, kStubbleY), 0);
    final out = smooth(pen);
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        if (!inStubble(x, y)) continue;
        final o = (y * _n + x) * 4;
        for (var c = 0; c < 3; c++) {
          if (out.data[o + c] != p.image.data[o + c]) {
            fail('stubble pixel $x,$y changed');
          }
        }
      }
    }
  });

  test('a paint stroke makes smoothing apply where the AI missed skin', () {
    final c = _face.toPx(kTintX, kTintY);
    double blotches(Float64List l) {
      var sum = 0.0;
      for (final (bx, by) in const [
        (-0.04, -0.03),
        (0.04, 0.02),
        (-0.02, 0.05),
      ]) {
        final q = _face.toPx(kTintX + bx, kTintY + by);
        sum += (discMean(l, _n, q.x, q.y, 2) - ringMean(l, _n, q.x, q.y, 5, 7))
            .abs();
      }
      return sum;
    }

    final before = blotches(labOf(p.image).l);
    expect(before, greaterThan(0.03));
    expect(blotches(labOf(smooth(base)).l) / before, greaterThan(0.95));
    final pen = applySkinPen(base, [_paintTint]);
    expect(skinAt(pen, kTintX, kTintY), greaterThan(0.9));
    expect(pen.sourceNearest(RetouchChannel.faceId, c.x / _n, c.y / _n), 1);
    expect(blotches(labOf(smooth(pen)).l) / before, lessThan(0.6));
  });

  test('strokes outside every face change nothing', () {
    final face = base.faces.single, t = base.transformOf(face);
    final left = (face.rect.x0 - t.tx) / t.sx * _n;
    expect(left, greaterThan(16), reason: 'room left of the work rect');
    const corner = BrushStroke(
      points: [(4 / _n, 0.1), (6 / _n, 0.6)],
      radius: 4 / _n,
      hardness: 1,
    );
    expect(identical(applySkinPen(base, [corner]), base), isTrue);
    expect(identical(applySkinPen(base, const []), base), isTrue);
  });

  test('blemishes centred in an erase stroke are not healed', () {
    final spot = kAcneSpots.first;
    final erase = _stroke(
      spot.x - 0.01,
      spot.x + 0.01,
      spot.y,
      0.05,
      erase: true,
    );
    final pen = applySkinPen(base, [erase]);
    final s = PortraitSettings.empty.withGroupValue(
      FaceGroup.all,
      PortraitIds.acne,
      100,
    );
    final out = labOf(
      applyRetouch(p.image, pen, RetouchUniforms.fromSettings(s, p.analysis)),
    );
    final before = labOf(p.image);
    double contrast(Float64List l, SynthSpot sp) {
      final q = _face.toPx(sp.x, sp.y), r = sp.radius * _face.iod;
      return (discMean(l, _n, q.x, q.y, 0.5 * r) -
              ringMean(l, _n, q.x, q.y, 2 * r, 3 * r))
          .abs();
    }

    expect(contrast(out.a, spot) / contrast(before.a, spot), greaterThan(0.9));
    final other = kAcneSpots[1];
    expect(contrast(out.a, other) / contrast(before.a, other), lessThan(0.3));
  });

  test('strokes apply in order, with flow and hardness', () {
    final paintThenErase = applySkinPen(base, [
      _paintTint,
      _stroke(kTintX - 0.05, kTintX + 0.05, kTintY, kTintR + 0.03, erase: true),
    ]);
    expect(skinAt(paintThenErase, kTintX, kTintY), 0);
    final halfFlow = applySkinPen(base, [
      _stroke(kTintX - 0.05, kTintX + 0.05, kTintY, kTintR + 0.03, flow: 0.5),
    ]);
    expect(skinAt(halfFlow, kTintX, kTintY), closeTo(0.5, 0.06));
    // Paint never adds skin over the eyes or lips.
    final eyes = applySkinPen(base, [_stroke(-0.6, 0.6, 0, 0.12)]);
    final iris = _face.toPx(-0.44, 0);
    expect(
      regionAt(
        eyes,
        RetouchChannel.skin,
        iris.x.floor(),
        iris.y.floor(),
        _n,
        _n,
      ),
      lessThan(0.05),
    );
  });

  test('computeRetouchMaps(skinPen:) equals applySkinPen on the base', () {
    final built = computeRetouchMaps(
      p.image,
      p.analysis,
      skinPen: [_eraseStubble, _paintTint],
    );
    final pen = applySkinPen(base, [_eraseStubble, _paintTint]);
    expect(built.regionA, pen.regionA);
    expect(built.regionB, pen.regionB);
    expect(
      identical(pen.deltaA, base.deltaA),
      isTrue,
      reason: 'deltas are shared',
    );
    expect(
      retouchImage(
        p.image,
        p.analysis,
        PortraitSettings.empty
            .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 100)
            .withSkinPen([_eraseStubble]),
      ).data,
      smooth(applySkinPen(base, [_eraseStubble])).data,
    );
  });

  test('region-limited face ids equal a full reassignment', () {
    final pen = applySkinPen(base, [_eraseStubble, _paintTint]);
    final rb = Uint8List.fromList(pen.regionB);
    final owner = faceOwners(pen.faces, pen.width, pen.height);
    for (final f in pen.faces) {
      assignFaceIds(f, pen.width, owner, pen.deltaB, pen.regionA, rb);
    }
    expect(rb, pen.regionB);
  });

  test('the brush matches the mask rasterizer', () {
    const stroke = BrushStroke(
      points: [(0.2, 0.3), (0.6, 0.45), (0.7, 0.8)],
      radius: 0.06,
      hardness: 0.4,
      flow: 0.7,
    );
    const w = 96, h = 64;
    final mask = MaskRasterizer.rasterize(
      const LocalMask(
        id: 'm',
        name: 'brush',
        kind: MaskKind.brush,
        strokes: [stroke],
      ),
      w,
      h,
    );
    final st = penStrokeStrength(stroke, const MapRect(0, 0, w, h), w, h)!;
    var worst = 0;
    for (var i = 0; i < w * h; i++) {
      worst = math.max(worst, ((st[i] * 255).round() - mask[i]).abs());
    }
    expect(worst, lessThanOrEqualTo(1));
  });
}
