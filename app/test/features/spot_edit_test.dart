import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/portrait/spot_edit_overlay.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

void main() {
  final p = renderSynthPortrait(512, 512, const [
    SynthFace(id: 'f', cx: 256, cy: 200, iod: 140),
  ]);
  final maps = computeRetouchMaps(p.image, p.analysis);
  final m = CanvasMapping(
    geometry: Geometry.none,
    source: const Size(512, 512),
    view: const Size(512, 512),
  );
  PortraitSettings withSliders(double acne, double freckle) => PortraitSettings
      .empty
      .withGroupValue(FaceGroup.all, PortraitIds.acne, acne)
      .withGroupValue(FaceGroup.all, PortraitIds.freckle, freckle);

  test('overlay heals what the sliders select', () {
    final none = layoutSpots(maps, p.analysis, PortraitSettings.empty, m);
    expect(none, isNotEmpty);
    expect(none.where((s) => s.healed), isEmpty);
    final acne = layoutSpots(maps, p.analysis, withSliders(100, 0), m);
    expect(
      acne.where((s) => s.healed).every((s) => s.spot.kind == BlemishKind.acne),
      isTrue,
    );
    expect(acne.where((s) => s.healed), isNotEmpty);
    // Circles sit on the spots, sized like them.
    for (final s in acne) {
      expect(s.center.dx, closeTo(s.spot.u * 512, 1e-6));
      expect(s.radius, greaterThanOrEqualTo(4));
    }
  });

  test('keep and remove anchors override the sliders', () {
    final acneSpot = maps.blemishes.firstWhere(
      (b) => b.kind == BlemishKind.acne,
    );
    final freckle = maps.blemishes.firstWhere(
      (b) => b.kind == BlemishKind.freckle,
    );
    final settings = withSliders(100, 0).withSpots(
      PortraitSpots.none.withKeep(acneSpot.anchor).withRemove(freckle.anchor),
    );
    final views = layoutSpots(maps, p.analysis, settings, m);
    expect(views.firstWhere((v) => v.spot.id == acneSpot.id).healed, isFalse);
    expect(views.firstWhere((v) => v.spot.id == freckle.id).healed, isTrue);
  });
}
