import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/remove/ai_remover.dart';
import 'package:lumen/features/remove/remove_service.dart';
import 'package:lumen/features/remove/remove_status.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';

/// What the last run is doing or did: a method chip with a spinner and
/// Cancel while running, the error after a failure, notes and the face
/// warning after it lands. Nothing when idle.
class RemoveStatusCard extends ConsumerWidget {
  const RemoveStatusCard({
    super.key,
    required this.assetId,
    this.touch = false,
  });

  static const faceWarning = 'Removing over a face can look unnatural.';

  final String assetId;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final status = ref.watch(removeStatusProvider(assetId));
    Widget line(IconData icon, Color color, String text) => Padding(
      padding: const EdgeInsets.only(top: Sp.s1_5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: Sp.s1_5),
          Expanded(
            child: Text(
              text,
              style: LumenType.body(touch: touch)
                  .copyWith(color: t.textSecondary),
            ),
          ),
        ],
      ),
    );
    return switch (status) {
      RemoveIdle() => const SizedBox.shrink(),
      RemoveRunning(:final kind, :final method) => Container(
        height: touch ? 48 : 36,
        padding: const EdgeInsets.only(left: Sp.s3),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            ),
            const SizedBox(width: Sp.s2),
            if (method == InpaintMethod.model) ...[
              const AiGlyph(size: 12),
              const SizedBox(width: Sp.s1),
            ],
            Expanded(
              child: Text(
                switch (kind) {
                  HealKind.remove when method != null => methodLabel(method),
                  HealKind.remove => 'Preparing…',
                  HealKind.heal => 'Healing…',
                  HealKind.clone => 'Cloning…',
                },
                overflow: TextOverflow.ellipsis,
                style: LumenType.label(touch: touch)
                    .copyWith(color: t.textPrimary),
              ),
            ),
            LumenButton(
              label: 'Cancel',
              kind: ButtonKind.ghost,
              height: touch ? 44 : 28,
              onPressed: () => ref.read(removeServiceProvider).cancel(assetId),
            ),
          ],
        ),
      ),
      RemoveFailed(:final message) => line(
        LucideIcons.circleAlert,
        t.danger,
        message,
      ),
      RemoveDone(:final note, :final faceIntersect) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (faceIntersect)
            line(LucideIcons.triangleAlert, t.warning, faceWarning),
          if (note != null) line(LucideIcons.info, t.textTertiary, note),
        ],
      ),
    };
  }
}

/// The AI fill switch and its model state (Remove tool only): download on
/// first use with progress, honest messages when it cannot run.
class AiFillRow extends ConsumerWidget {
  const AiFillRow({super.key, this.touch = false});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ai = ref.watch(aiRemoverProvider);
    final ctl = ref.read(aiRemoverProvider.notifier);
    final size = megabytes(ref.read(aiRemoverLoaderProvider).downloadBytes);
    final caption = LumenType.caption(touch: touch)
        .copyWith(color: t.textTertiary);
    if (ai.phase == AiRemoverPhase.unavailable) {
      return Text(ai.message ?? '', style: caption);
    }
    final subtitle = switch (ai.phase) {
      AiRemoverPhase.downloading => 'Downloading AI remover · $size',
      AiRemoverPhase.loading => 'Starting the AI remover…',
      AiRemoverPhase.checking => 'Checking for the AI remover…',
      AiRemoverPhase.failed => ai.message ?? 'AI remover unavailable.',
      AiRemoverPhase.ready when ai.enabled =>
        'Large objects are filled by the on-device AI model.',
      AiRemoverPhase.ready => 'Classic fill only.',
      _ => 'Better fills for large objects · $size download, stays on device.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AiGlyph(size: 14),
            const SizedBox(width: Sp.s1_5),
            Expanded(
              child: Text(
                'AI fill',
                style: LumenType.label(touch: touch)
                    .copyWith(color: t.textPrimary),
              ),
            ),
            if (ai.phase == AiRemoverPhase.downloading)
              LumenButton(
                label: 'Cancel',
                kind: ButtonKind.ghost,
                height: touch ? 44 : 28,
                onPressed: ctl.cancelDownload,
              )
            else
              Semantics(
                label: 'AI fill',
                toggled: ai.enabled,
                child: Switch(
                  value: ai.enabled,
                  activeTrackColor: t.accent,
                  onChanged: ai.busy
                      ? null
                      : (on) => on ? ctl.enable() : ctl.disable(),
                ),
              ),
          ],
        ),
        Text(subtitle, style: caption),
        if (ai.phase == AiRemoverPhase.downloading ||
            ai.phase == AiRemoverPhase.loading)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s1),
            child: LinearProgressIndicator(
              value: ai.phase == AiRemoverPhase.loading ? null : ai.progress,
              minHeight: 2,
              color: t.accent,
              backgroundColor: t.surface3,
            ),
          ),
      ],
    );
  }
}
