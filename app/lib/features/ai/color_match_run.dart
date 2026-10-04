import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/ai/color_match_service.dart';
import 'package:lumen/features/editor/editor_controller.dart';

/// Matches the open photo [assetId] to [reference]'s look: ONE AI history
/// entry ("Color match · [name]") with AI Amount. Sliders the user set by
/// hand since the last AI step are kept; portrait retouch is untouched.
/// Returns the number of sliders changed (null: the photo is not open).
Future<int?> runColorMatch(
  WidgetRef ref,
  String assetId,
  CatalogEntry reference,
) async {
  final ctl = ref.read(editorProvider(assetId).notifier);
  final state = ref.read(editorProvider(assetId)).value;
  if (state == null) return null;
  final service = ref.read(colorMatchServiceProvider);
  ctl.setAiBusy(true, status: 'Matching the look…');
  try {
    final look = await service.lookOf(reference.assetId);
    final proxy = await service.proxyOf(assetId, state.settings);
    final r = await service.match(
      proxy,
      state.settings,
      look,
      locked: state.lockedByUser,
    );
    // Apply onto the latest settings (edits made meanwhile are kept).
    final now = ref.read(editorProvider(assetId)).value?.settings;
    if (now == null) return null;
    final next = now.withValues({
      for (final p in ColorMatch.managedParams) p: r.settings.value(p),
    });
    ctl.applyAi(
      next,
      ColorMatchService.recordFor(now, r),
      label: ColorMatchService.labelFor(reference),
    );
    return r.changes.length;
  } finally {
    ctl.setAiBusy(false);
  }
}
