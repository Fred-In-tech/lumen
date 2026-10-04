import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/remove/heal_commands.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// One heal op in the Remove list: kind icon, name and engine, an AI badge
/// for model fills, a face warning, and hide/show and delete (each one
/// history entry).
class HealOpRow extends ConsumerWidget {
  const HealOpRow({
    super.key,
    required this.assetId,
    required this.op,
    required this.all,
    this.touch = false,
  });

  final String assetId;
  final HealOp op;

  /// Every op in document order (names are numbered by kind).
  final List<HealOp> all;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cmds = HealCommands(ref.read, assetId);
    final btn = touch ? 36.0 : 28.0;
    final iconSize = touch ? 18.0 : 16.0;
    final name = HealCommands.nameOf(all, op);
    final dim = op.hidden ? t.textTertiary : t.textPrimary;
    return Container(
      height: touch ? 48 : 36,
      padding: const EdgeInsets.only(left: Sp.s2),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(Rad.sm),
      ),
      child: Row(
        children: [
          Icon(healKindIcon(op.kind), size: iconSize, color: t.textSecondary),
          const SizedBox(width: Sp.s2),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: name,
                    style: LumenType.body(touch: touch).copyWith(color: dim),
                  ),
                  TextSpan(
                    text: '  ${engineLabel(op.engine)}',
                    style: LumenType.caption(touch: touch)
                        .copyWith(color: t.textTertiary),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (op.ai)
            Tooltip(
              message: 'Made by the on-device AI model',
              child: Container(
                margin: const EdgeInsets.only(right: Sp.s1),
                padding: const EdgeInsets.symmetric(
                  horizontal: Sp.s1_5,
                  vertical: Sp.s0_5,
                ),
                decoration: BoxDecoration(
                  color: t.surface3,
                  borderRadius: BorderRadius.circular(Rad.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AiGlyph(size: 10),
                    const SizedBox(width: Sp.s0_5),
                    Text(
                      'AI',
                      style: LumenType.micro().copyWith(color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          if (op.faceIntersect)
            Tooltip(
              message: 'Removing over a face can look unnatural',
              child: Padding(
                padding: const EdgeInsets.only(right: Sp.s1),
                child: Icon(
                  LucideIcons.triangleAlert,
                  size: iconSize - 2,
                  color: t.warning,
                ),
              ),
            ),
          LumenIconButton(
            icon: op.hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            tooltip: op.hidden ? 'Show $name' : 'Hide $name',
            size: btn,
            iconSize: iconSize,
            onPressed: () => cmds.toggleHidden(op.id),
          ),
          LumenIconButton(
            icon: LucideIcons.trash2,
            tooltip: 'Delete $name',
            size: btn,
            iconSize: iconSize,
            onPressed: () {
              final deleted = cmds.delete(op.id);
              if (deleted == null) return;
              showToast(
                context,
                'Deleted $deleted.',
                actionLabel: 'Undo',
                onAction: ref.read(editorProvider(assetId).notifier).undo,
              );
            },
          ),
        ],
      ),
    );
  }
}
