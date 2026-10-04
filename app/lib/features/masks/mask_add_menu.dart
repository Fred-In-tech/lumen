import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/masks/mask_kinds.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// "Add mask" button + menu: manual kinds, then AI kinds from the
/// [aiMaskSourceProvider] seam (disabled with an honest hint while the
/// on-device model is missing).
class AddMaskMenu extends ConsumerWidget {
  const AddMaskMenu({
    super.key,
    required this.assetId,
    required this.count,
    this.sourceSize = const Size(1, 1),
    this.touch = false,
  });

  final String assetId;
  final int count;
  final Size sourceSize;
  final bool touch;

  static const fullHint = '8 masks is the limit. Delete one to add another.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final full = count >= LocalMask.maxMasks;
    return Pressable(
      onTap: full ? null : () => _open(context, ref),
      tooltip: full ? fullHint : null,
      semanticLabel: 'Add mask',
      builder: (context, states) => Container(
        height: touch ? 44 : 32,
        padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered) ? t.surface3 : t.surface2,
          borderRadius: BorderRadius.circular(Rad.sm),
          border: Border.all(color: t.lineStrong),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.plus, size: 16, color: t.textPrimary),
            const SizedBox(width: Sp.s1_5),
            Expanded(
              child: Text(
                'Add mask',
                style: LumenType.button(touch: touch)
                    .copyWith(color: t.textPrimary),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: t.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final t = context.tokens;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(
      Offset(0, box.size.height + Sp.s1),
      ancestor: overlay,
    );
    final source = ref.read(aiMaskSourceProvider);
    final itemHeight = touch ? 48.0 : 36.0;
    PopupMenuItem<MaskKind> item(MaskKind k, {bool ai = false}) {
      final enabled = !ai || (source?.supports(k) ?? false);
      return PopupMenuItem<MaskKind>(
        value: k,
        enabled: enabled,
        height: ai && !enabled ? itemHeight + 8 : itemHeight,
        child: _MenuRow(
          kind: k,
          enabled: enabled,
          hint: enabled ? null : kAiMaskUnavailableHint,
          touch: touch,
        ),
      );
    }

    final kind = await showMenu<MaskKind>(
      context: context,
      color: t.surface3,
      constraints: BoxConstraints(minWidth: box.size.width, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.md),
        side: BorderSide(color: t.line),
      ),
      position: RelativeRect.fromRect(
        topLeft & Size(box.size.width, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final k in kManualMaskKinds) item(k),
        const PopupMenuDivider(height: Sp.s2),
        PopupMenuItem<MaskKind>(
          enabled: false,
          height: 28,
          child: Row(
            children: [
              AiGlyph(size: 12, neutral: source == null),
              const SizedBox(width: Sp.s1_5),
              Text(
                'AI masks',
                style: LumenType.caption().copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
        for (final k in kAiMaskKinds) item(k, ai: true),
      ],
    );
    if (kind == null || !context.mounted) return;
    await _add(context, ref, kind);
  }

  Future<void> _add(BuildContext context, WidgetRef ref, MaskKind kind) async {
    final cmds = MaskCommands.of(ref, assetId);
    if (!kind.isAi) {
      cmds.add(kind, sourceSize: sourceSize);
      return;
    }
    final source = ref.read(aiMaskSourceProvider);
    if (source == null || !source.supports(kind)) return;
    try {
      final shape = await source.segment(assetId, kind);
      if (!context.mounted) return;
      cmds.add(kind, sourceSize: sourceSize, ai: shape);
    } on Exception {
      if (!context.mounted) return;
      showToast(
        context,
        'Couldn’t make a ${kind.menuLabel.toLowerCase()} mask for this photo.',
        kind: ToastKind.error,
      );
    }
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.kind,
    required this.enabled,
    required this.touch,
    this.hint,
  });

  final MaskKind kind;
  final bool enabled;
  final bool touch;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = enabled ? t.textPrimary : t.textDisabled;
    return Semantics(
      enabled: enabled,
      hint: hint,
      child: Row(
        children: [
          Icon(kind.icon, size: 16, color: enabled ? t.textSecondary : fg),
          const SizedBox(width: Sp.s2),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind.menuLabel,
                  style: LumenType.bodyStrong(touch: touch).copyWith(color: fg),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: LumenType.caption().copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
