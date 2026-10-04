import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/canvas/mask_painter.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';

/// Radius (IOD units) of a spot the user marks on bare skin.
const double kManualSpotRadiusIod = 0.03;

/// One detected spot as the overlay shows it.
typedef SpotView = ({
  BlemishCandidate spot,
  Offset center,
  double radius,
  bool healed,
});

/// Lays out [maps]' spots in view space and decides which will heal under
/// [portrait] (sliders of the spot's face group or person, plus the user's
/// keep / remove anchors). Mirrors the engine's selection.
List<SpotView> layoutSpots(
  RetouchMaps maps,
  FaceAnalysis faces,
  PortraitSettings portrait,
  CanvasMapping m,
) {
  final views = <SpotView>[];
  for (final c in maps.blemishes) {
    final info = maps.faceInSlot(c.slot);
    if (info == null) continue;
    final face = faces.faceById(c.faceId);
    double slider(String id) =>
        portrait.valueFor(
          id,
          group: face?.group ?? FaceGroup.all,
          personId: face?.personId ?? face?.id,
        ) /
        100;
    final iodUv = info.iod / maps.width;
    final tol = (kAnchorMatchIod + 0.5 * c.radiusIod) * iodUv;
    bool near(SpotAnchor a) =>
        math.sqrt(math.pow(a.u - c.u, 2) + math.pow(a.v - c.v, 2)) <=
        tol + 0.5 * a.radiusIod * iodUv;
    final kept = portrait.spots.keep.any(near);
    final removed = portrait.spots.remove.any(near);
    final selected = spotSelection(
      encodeSpotCode(c.kind, c.threshold),
      slider(PortraitIds.acne),
      slider(PortraitIds.freckle),
      slider(PortraitIds.mole),
    );
    final center = m.toView(c.u, c.v);
    final edge = m.toView(c.u + c.radiusIod * iodUv, c.v);
    views.add((
      spot: c,
      center: center,
      radius: math.max(4, (edge - center).distance),
      healed: !kept && (removed || selected >= 0.5),
    ));
  }
  return views;
}

/// Spot editor: every detected blemish, freckle and mole as a circle
/// (filled = will be removed). Click a spot to flip it; click bare skin to
/// remove something the detector missed. Decisions are saved by position.
class SpotEditOverlay extends ConsumerWidget {
  const SpotEditOverlay({
    super.key,
    required this.assetId,
    required this.mapping,
  });

  final String assetId;
  final CanvasMapping mapping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final inputs = ref.watch(retouchInputsProvider(assetId));
    final portrait = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.settings.portrait ?? PortraitSettings.empty),
    );
    final data = inputs.value;
    if (data == null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(Sp.s3),
          child: _Chip(
            inputs.isLoading ? 'Finding spots…' : 'No face to edit spots on',
          ),
        ),
      );
    }
    final spots = layoutSpots(data.maps, data.faces, portrait, mapping);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onTap(ref, data, spots, d.localPosition),
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpotPainter(spots: spots, healed: t.success),
      ),
    );
  }

  void _onTap(
    WidgetRef ref,
    RetouchInputs data,
    List<SpotView> spots,
    Offset p,
  ) {
    final s = ref.read(editorProvider(assetId)).value?.settings;
    if (s == null) return;
    SpotView? hit;
    var best = double.infinity;
    for (final v in spots) {
      final d = (v.center - p).distance;
      if (d <= v.radius + 10 && d < best) {
        best = d;
        hit = v;
      }
    }
    final PortraitSpots next;
    final String label;
    if (hit != null) {
      final a = hit.spot.anchor;
      next = hit.healed
          ? s.portrait.spots.withKeep(a)
          : s.portrait.spots.withRemove(a);
      label = hit.healed ? 'Keep spot' : 'Remove spot';
    } else {
      final (u, v) = mapping.toSource(p);
      final onFace = data.faces.faces.any(
        (f) =>
            u >= f.box.x &&
            u <= f.box.x + f.box.width &&
            v >= f.box.y &&
            v <= f.box.y + f.box.height,
      );
      if (!onFace) return;
      next = s.portrait.spots.withRemove(
        SpotAnchor(u, v, kManualSpotRadiusIod),
      );
      label = 'Remove spot';
    }
    ref
        .read(editorProvider(assetId).notifier)
        .commit(s.copyWith(portrait: s.portrait.withSpots(next)), label: label);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Sp.s2, vertical: 3),
    decoration: BoxDecoration(
      color: CanvasInk.pinFill,
      borderRadius: BorderRadius.circular(Rad.pill),
    ),
    child: Text(text, style: LumenType.micro().copyWith(color: Colors.white)),
  );
}

class _SpotPainter extends CustomPainter {
  _SpotPainter({required this.spots, required this.healed});

  final List<SpotView> spots;
  final Color healed;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in spots) {
      canvas.drawCircle(
        s.center,
        s.radius + 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = CanvasInk.halo,
      );
      if (s.healed) {
        canvas.drawCircle(
          s.center,
          s.radius,
          Paint()..color = healed.withValues(alpha: 0.35),
        );
      }
      canvas.drawCircle(
        s.center,
        s.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = s.healed ? healed : CanvasInk.line,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.healed != healed || !identical(old.spots, spots);
}
