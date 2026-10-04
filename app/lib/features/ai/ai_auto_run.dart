import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/features/ai/auto_retouch.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';

/// "Auto" for the open photo: the colour auto-edit (local, then vision)
/// and, when "Retouch faces automatically" is on and the photo has faces,
/// need-scaled Auto Retouch, applied together as ONE undoable AI step.
Future<AiRunResult?> runAiAuto(
  WidgetRef ref,
  EditorSession session, {
  AiStyle style = AiStyle.natural,
}) async {
  final id = session.assetId;
  final ctl = ref.read(editorProvider(id).notifier);
  final state = ref.read(editorProvider(id)).value;
  if (state == null) return null;
  final base = await session.aiContext(state);
  if (base == null) return null;
  final retouchFaces =
      ref.read(settingsProvider).value?.retouchFacesAutomatically ?? true;
  final planner = ref.read(autoRetouchPlannerProvider);
  final ctx = retouchFaces
      ? base.copyWith(retouch: () => planner.plan(id, state.doc))
      : base;
  final service = ref.read(autoEditServiceProvider);
  ctl.setAiBusy(
    true,
    status: service.visionAvailable ? 'Reading the light…' : 'Developing…',
  );
  try {
    final result = await service.autoEdit(
      ctx,
      style: style,
      onLocal: (local) {
        if (service.visionAvailable) {
          ctl.preview(local.settings);
          ctl.setAiBusy(true, status: 'Developing…');
        } else if (retouchFaces) {
          ctl.setAiBusy(true, status: 'Retouching faces…');
        }
      },
    );
    // Back to the start, so the history entry spans colour + retouch.
    ctl.preview(state.settings);
    ctl.applyAi(result.outcome.settings, result.record, label: result.label);
    return result;
  } finally {
    ctl.setAiBusy(false);
  }
}

/// [applyAiAmount] that also scales the AI's portrait retouch (never past
/// 100 %: retouch is not extrapolated).
DevelopSettings applyAiAmountWithRetouch({
  required DevelopSettings pre,
  required DevelopSettings ai,
  required double percent,
}) {
  final colour = applyAiAmount(pre: pre, ai: ai, percent: percent);
  if (pre.portrait == ai.portrait) return colour;
  final t = (percent.clamp(kAiAmountMin, kAiAmountMax) / 100).clamp(0.0, 1.0);
  return colour.copyWith(
    portrait: PortraitSettings.lerp(pre.portrait, ai.portrait, t),
  );
}
