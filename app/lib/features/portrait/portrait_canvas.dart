import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/portrait/face_boxes_overlay.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/portrait/spot_edit_overlay.dart';

/// Portrait canvas tools: face boxes, or the spot editor while it is on.
class PortraitCanvas extends ConsumerWidget {
  const PortraitCanvas({
    super.key,
    required this.assetId,
    required this.mapping,
  });

  final String assetId;
  final CanvasMapping mapping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotEdit = ref.watch(
      portraitUiProvider(assetId).select((u) => u.spotEdit),
    );
    return spotEdit
        ? SpotEditOverlay(assetId: assetId, mapping: mapping)
        : FaceBoxesOverlay(assetId: assetId, mapping: mapping);
  }
}
