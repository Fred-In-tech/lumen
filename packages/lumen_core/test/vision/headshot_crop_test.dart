import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_face.dart';

const _w = 1000, _h = 800;

DetectedFace face(
  double cx,
  double cy, {
  double iod = 60,
  double roll = 0,
  String id = 'f',
}) => DetectedFace(
  id: id,
  box: FaceBox(
    (cx - iod) / _w,
    (cy - 0.6 * iod) / _h,
    2 * iod / _w,
    2 * iod / _h,
  ),
  landmarks: syntheticLandmarks(
    imageWidth: _w,
    imageHeight: _h,
    cx: cx,
    cy: cy,
    iod: iod,
    rollDegrees: roll,
  ),
);

/// Crop-normalized point → source uv, through the renderer's own mapping.
(double, double) toSource(Geometry g, double u, double v) {
  final f = Float32List(DevelopIndex.src + 4);
  f.setAll(DevelopIndex.crop, [
    g.crop.left,
    g.crop.top,
    g.crop.right,
    g.crop.bottom,
  ]);
  f.setAll(DevelopIndex.geom, [
    g.angle * math.pi / 180,
    g.rotate90.toDouble(),
    g.flipH ? 1 : 0,
    g.flipV ? 1 : 0,
  ]);
  f.setAll(DevelopIndex.src, [_w.toDouble(), _h.toDouble(), 0, 0]);
  return sourceUvFor(u, v, f);
}

(double, double) lm(DetectedFace f, int i) =>
    (f.landmarks[2 * i], f.landmarks[2 * i + 1]);

(double, double) eyeMid(DetectedFace f) {
  final r = lm(f, MeshKeypoints.rightIrisCenter);
  final l = lm(f, MeshKeypoints.leftIrisCenter);
  return ((r.$1 + l.$1) / 2, (r.$2 + l.$2) / 2);
}

double pixelAspect(Geometry g) {
  final dw = g.swapsAxes ? _h : _w, dh = g.swapsAxes ? _w : _h;
  return g.crop.width * dw / (g.crop.height * dh);
}

void expectNear((double, double) a, (double, double) b, {double px = 0.5}) {
  expect(a.$1 * _w, closeTo(b.$1 * _w, px));
  expect(a.$2 * _h, closeTo(b.$2 * _h, px));
}

HeadshotCrop crop(
  List<DetectedFace> faces, {
  HeadshotRatio ratio = HeadshotRatio.portrait4x5,
  Geometry current = Geometry.none,
}) => headshotCrop(
  faces: faces,
  sourceWidth: _w,
  sourceHeight: _h,
  ratio: ratio,
  current: current,
)!;

void main() {
  test('one upright face: eyes on the upper third, centred, ratio kept', () {
    final f = face(500, 360);
    for (final ratio in HeadshotRatio.values) {
      final c = crop([f], ratio: ratio);
      final g = c.geometry;
      expect(g.angle, 0);
      expect(g.aspect, ratio.id);
      expect(c.clipped, isFalse);
      expect(pixelAspect(g), closeTo(ratio.value, 1e-6));
      expectNear(toSource(g, 0.5, 1 / 3), eyeMid(f));
    }
    // Head room: the crown (one eye-chin distance above the eyes) is below
    // the top by at least 8 % of the crop height.
    final g = crop([f]).geometry;
    final eyeY = eyeMid(f).$2 * _h;
    final d = lm(f, MeshKeypoints.chin).$2 * _h - eyeY;
    final top = g.crop.top * _h, height = g.crop.height * _h;
    expect((eyeY - d - top) / height, greaterThanOrEqualTo(0.08 - 1e-9));
  });

  test('a rolled face is levelled: both irises on the eye line', () {
    final f = face(480, 380, roll: 3);
    final c = crop([f]);
    expect(c.rollDegrees, closeTo(3, 1e-9));
    expect(c.geometry.angle, closeTo(-3, 1e-9));
    expectNear(toSource(c.geometry, 0.5, 1 / 3), eyeMid(f));
    // Points along the crop's eye line pass through both iris centres.
    final a = toSource(c.geometry, 0.0, 1 / 3);
    final b = toSource(c.geometry, 1.0, 1 / 3);
    double off((double, double) p) {
      final dx = (b.$1 - a.$1) * _w, dy = (b.$2 - a.$2) * _h;
      final px = (p.$1 - a.$1) * _w, py = (p.$2 - a.$2) * _h;
      return (dx * py - dy * px).abs() / math.sqrt(dx * dx + dy * dy);
    }

    expect(off(lm(f, MeshKeypoints.rightIrisCenter)), lessThan(0.05));
    expect(off(lm(f, MeshKeypoints.leftIrisCenter)), lessThan(0.05));
  });

  test('straightening is limited to ±5° and never shows the outside', () {
    final f = face(160, 150, roll: -12);
    final c = crop([f]);
    expect(c.rollDegrees, closeTo(-12, 1e-9));
    expect(c.geometry.angle, 5);
    for (final (u, v) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]) {
      final (x, y) = toSource(c.geometry, u, v);
      expect(x, inInclusiveRange(-1e-4, 1 + 1e-4));
      expect(y, inInclusiveRange(-1e-4, 1 + 1e-4));
    }
  });

  test('three faces are framed together', () {
    final faces = [
      face(250, 400, id: 'a'),
      face(500, 380, id: 'b', iod: 70),
      face(750, 420, id: 'c'),
    ];
    final g = crop(faces, ratio: HeadshotRatio.square).geometry;
    expect(pixelAspect(g), closeTo(1, 1e-6));
    for (final f in faces) {
      final eye = eyeMid(f), chin = lm(f, MeshKeypoints.chin);
      final crown = eye.$2 - (chin.$2 - eye.$2);
      for (final (x, y) in [eye, chin, (eye.$1, crown)]) {
        expect(x, inInclusiveRange(g.crop.left, g.crop.right), reason: f.id);
        expect(y, inInclusiveRange(g.crop.top, g.crop.bottom), reason: f.id);
      }
    }
  });

  test('a face at the border shifts the crop inside the photo', () {
    final f = face(110, 90);
    final c = crop([f]);
    final r = c.geometry.crop;
    expect(c.clipped, isFalse);
    expect(r.left, closeTo(0, 1e-9));
    expect(r.top, closeTo(0, 1e-9));
    expect(pixelAspect(c.geometry), closeTo(0.8, 1e-6));
    final eye = eyeMid(f);
    expect(eye.$1, inInclusiveRange(r.left, r.right));
    expect(eye.$2, inInclusiveRange(r.top, r.bottom));
  });

  test('a face too big for the frame is clipped to the photo', () {
    final c = crop([face(500, 300, iod: 260)]);
    expect(c.clipped, isTrue);
    final r = c.geometry.crop;
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(1));
    expect(r.height, closeTo(1, 1e-6));
    expect(pixelAspect(c.geometry), closeTo(0.8, 1e-6));
  });

  test('quarter turns and flips: a face upright after them is framed', () {
    // Source roll that makes the face upright (+2°) once the quarter turns
    // and flips are applied.
    for (final (current, base) in const [
      (Geometry(rotate90: 1), -90.0),
      (Geometry(rotate90: 2, flipH: true), 180.0),
      (Geometry(rotate90: 3, flipV: true), -90.0),
    ]) {
      final f = face(420, 350, roll: base + 2);
      final c = crop([f], current: current);
      final g = c.geometry;
      expect(g.rotate90, current.rotate90);
      expect(g.flipH, current.flipH);
      expect(g.flipV, current.flipV);
      expect(pixelAspect(g), closeTo(0.8, 1e-6));
      expect(g.angle.abs(), closeTo(2, 1e-6));
      expectNear(toSource(g, 0.5, 1 / 3), eyeMid(f), px: 1);
    }
  });

  test('box-only faces fall back to the detector box; no faces → null', () {
    const boxOnly = DetectedFace(id: 'b', box: FaceBox(0.45, 0.4, 0.1, 0.12));
    final c = crop([boxOnly]);
    expect(c.geometry.angle, 0);
    final r = c.geometry.crop;
    expect(boxOnly.box.centerX, closeTo((r.left + r.right) / 2, 1e-9));
    expect(
      headshotCrop(
        faces: const [],
        sourceWidth: _w,
        sourceHeight: _h,
        ratio: HeadshotRatio.square,
      ),
      isNull,
    );
  });
}
