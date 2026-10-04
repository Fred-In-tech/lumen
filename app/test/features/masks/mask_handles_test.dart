import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/masks/canvas/mask_handles.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen_core/lumen_core.dart';

const _src = Size(400, 200);

RadialShape _drag(
  HandleRole role,
  RadialShape s,
  (double, double) from,
  (double, double) to,
) => RadialShape.fromJson(
  dragShape(role, MaskKind.radial, s.toJson(), from, to, _src),
);

void main() {
  const circle = RadialShape(cx: 0.5, cy: 0.5, rx: 0.1, ry: 0.2); // 40 px

  test('the rotate knob turns the ellipse by the pointer angle', () {
    // From straight above the centre to straight right: +90° in pixels.
    final r = _drag(
      HandleRole.radialRotate,
      circle,
      (0.5, 0.5 - 60 / 200),
      (0.5 + 60 / 400, 0.5),
    );
    expect(r.angle, closeTo(90, 1e-9));
    expect(r.rx, circle.rx);
  });

  test('axis handles resize symmetrically along their own axis', () {
    final wider = _drag(
      HandleRole.radialRx,
      circle,
      (0.6, 0.5),
      (0.6 + 20 / 400, 0.5 + 0.1),
    );
    expect(wider.rx * _src.width, closeTo(60, 1e-9));
    expect(wider.ry, circle.ry);
    final taller = _drag(
      HandleRole.radialRyNeg,
      circle,
      (0.5, 0.3),
      (0.5, 0.3 - 10 / 200),
    );
    expect(taller.ry * _src.height, closeTo(50, 1e-9));
  });

  test('a rotated ellipse resizes along its rotated axis', () {
    const tilted = RadialShape(cx: 0.5, cy: 0.5, rx: 0.1, ry: 0.2, angle: 90);
    // The x axis now points down: dragging +x handle down grows rx.
    final r = _drag(
      HandleRole.radialRx,
      tilted,
      (0.5, 0.5 + 40 / 200),
      (0.5, 0.5 + 70 / 200),
    );
    expect(r.rx * _src.width, closeTo(70, 1e-9));
  });

  test('the feather knob sets the solid fraction from its radius', () {
    const s = RadialShape(cx: 0.5, cy: 0.5, rx: 0.1, ry: 0.2, feather: 0.5);
    // Inner ellipse at e = 0.5; drag outwards along x by 10 px of 40.
    final r = _drag(
      HandleRole.radialFeather,
      s,
      (0.5 + 20 / 400, 0.5),
      (0.5 + 30 / 400, 0.5),
    );
    expect(r.feather, closeTo(0.25, 1e-9));
    final clamped = _drag(
      HandleRole.radialFeather,
      s,
      (0.5 + 20 / 400, 0.5),
      (0.5 + 200 / 400, 0.5),
    );
    expect(clamped.feather, 0);
  });

  test('radii never collapse below 2 px', () {
    final r = _drag(HandleRole.radialRx, circle, (0.6, 0.5), (0.2, 0.5));
    expect(r.rx * _src.width, closeTo(2, 1e-9));
  });

  test('linear endpoints move independently, the pin moves both', () {
    const s = LinearShape(x0: 0.5, y0: 0.1, x1: 0.5, y1: 0.4);
    LinearShape drag(HandleRole role) => LinearShape.fromJson(
      dragShape(
        role,
        MaskKind.linear,
        s.toJson(),
        (0.5, 0.5),
        (0.6, 0.55),
        _src,
      ),
    );
    final a = drag(HandleRole.linearStart);
    expect(a.x0, closeTo(0.6, 1e-12));
    expect(a.y0, closeTo(0.15, 1e-12));
    expect((a.x1, a.y1), (0.5, 0.4));
    final b = drag(HandleRole.linearEnd);
    expect((b.x0, b.y0), (0.5, 0.1));
    expect(b.x1, closeTo(0.6, 1e-12));
    final m = drag(HandleRole.linearMove);
    expect(m.x0, closeTo(0.6, 1e-12));
    expect(m.y1, closeTo(0.45, 1e-12));
  });

  test('guides: the three linear lines are perpendicular to the gradient', () {
    final map = CanvasMapping(
      geometry: const Geometry(angle: 20, flipH: true),
      source: _src,
      view: const Size(400, 200),
    );
    final g = LinearGuide.of(
      const LinearShape(x0: 0.3, y0: 0.2, x1: 0.6, y1: 0.7),
      map,
    );
    final d = g.b - g.a;
    expect(d.dx * g.normal.dx + d.dy * g.normal.dy, closeTo(0, 1e-9));
    expect(g.normal.distance, closeTo(1, 1e-12));
  });

  test('radial handles sit on the drawn ellipse under any geometry', () {
    final map = CanvasMapping(
      geometry: const Geometry(angle: -15, rotate90: 3, flipV: true),
      source: _src,
      view: const Size(250, 500),
    );
    const s = RadialShape(cx: 0.4, cy: 0.6, rx: 0.15, ry: 0.1, angle: 30);
    final g = RadialGuide.of(s, map);
    // Axis vectors stay perpendicular (similarity) …
    expect(g.xAxis.dx * g.yAxis.dx + g.xAxis.dy * g.yAxis.dy, closeTo(0, 1e-6));
    // … and scale the source radii uniformly.
    expect(g.rx / (s.rx * _src.width), closeTo(map.scale, 1e-9));
    expect(g.ry / (s.ry * _src.height), closeTo(map.scale, 1e-9));
    final scene = MaskScene.build(
      [LocalMask(id: 'r', name: 'R', kind: MaskKind.radial, shape: s.toJson())],
      LocalMask(id: 'r', name: 'R', kind: MaskKind.radial, shape: s.toJson()),
      map,
      touch: false,
    );
    expect(scene.hit(g.center + g.xAxis, 12)?.role, HandleRole.radialRx);
    expect(scene.hit(g.center, 12)?.role, HandleRole.radialMove);
  });

  test('default shapes land in the visible frame under any geometry', () {
    for (final q in [0, 1, 2, 3]) {
      final geo = Geometry(
        rotate90: q,
        angle: 10,
        crop: const CropRect(0.2, 0.1, 0.9, 0.8),
      );
      final map = CanvasMapping.output(geo, _src);
      final r = RadialShape.fromJson(
        defaultMaskShape(MaskKind.radial, geo, _src),
      );
      final c = map.toView(r.cx, r.cy);
      expect(c.dx, closeTo(map.view.width / 2, 1e-6));
      expect(c.dy, closeTo(map.view.height / 2, 1e-6));
      // The ellipse's x axis is horizontal on screen.
      final g = RadialGuide.of(r, map);
      expect(math.sin(g.rotation).abs(), closeTo(0, 1e-6));
      final l = LinearShape.fromJson(
        defaultMaskShape(MaskKind.linear, geo, _src),
      );
      final a = map.toView(l.x0, l.y0), b = map.toView(l.x1, l.y1);
      expect(a.dx, closeTo(b.dx, 1e-6));
      expect(a.dy, lessThan(b.dy));
    }
  });
}
