import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/portrait/face_boxes_overlay.dart';
import 'package:lumen_core/lumen_core.dart';

const _big = DetectedFace(id: 'big', box: FaceBox(0.2, 0.2, 0.5, 0.5));
const _small = DetectedFace(id: 'small', box: FaceBox(0.4, 0.4, 0.1, 0.1));

void main() {
  test('hit test picks the smallest face under the point', () {
    final m = CanvasMapping(
      geometry: Geometry.none,
      source: const Size(1000, 800),
      view: const Size(500, 400),
    );
    expect(
      FaceBoxesOverlay.hitTest([_big, _small], m, const Offset(225, 180))?.id,
      'small',
    );
    expect(
      FaceBoxesOverlay.hitTest([_big, _small], m, const Offset(120, 100))?.id,
      'big',
    );
    expect(
      FaceBoxesOverlay.hitTest([_big, _small], m, const Offset(10, 10)),
      isNull,
    );
  });

  test('boxes follow crop and quarter turns like the renderer', () {
    const geometry = Geometry(
      crop: CropRect(0.1, 0.1, 0.9, 0.9),
      rotate90: 1,
      flipH: true,
    );
    final m = CanvasMapping(
      geometry: geometry,
      source: const Size(1000, 800),
      view: const Size(400, 500),
    );
    for (final corner in FaceBoxesOverlay.quadOf(_small, m)) {
      final (u, v) = m.toSource(corner);
      final onEdge =
          (u - 0.4).abs() < 1e-4 ||
          (u - 0.5).abs() < 1e-4 ||
          (v - 0.4).abs() < 1e-4 ||
          (v - 0.5).abs() < 1e-4;
      expect(onEdge, isTrue, reason: '($u, $v)');
    }
    final centre = m.toView(_small.box.centerX, _small.box.centerY);
    expect(FaceBoxesOverlay.hitTest([_small], m, centre)?.id, 'small');
  });
}
