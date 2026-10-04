import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/mask_add_menu.dart';
import 'package:lumen/features/masks/mask_editor.dart';
import 'package:lumen/features/masks/mask_row.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';

/// The Masks module (Lightroom-style local adjustments): an "Add mask" menu,
/// the mask list (max [LocalMask.maxMasks]) and the selected mask's
/// controls. Shapes are edited on the canvas (`ModuleOverlay`).
class MasksPanel extends ConsumerWidget {
  const MasksPanel({
    super.key,
    required this.assetId,
    this.sourceSize = const Size(1, 1),
    this.touch = false,
  });

  final String assetId;

  /// Source pixel size (its aspect places new gradients in the frame).
  final Size sourceSize;
  final bool touch;

  static const emptyHint =
      'Masks adjust just part of the photo: a sky, a face, one corner.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final masks = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.settings.masks ?? const <LocalMask>[]),
    );
    final ui = ref.watch(maskUiProvider(assetId));
    final selected = ui.selectedIn(masks);
    final pad = touch ? 0.0 : Sp.s4;
    final canAdd = masks.length < LocalMask.maxMasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, Sp.s2, pad, Sp.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AddMaskMenu(
                      assetId: assetId,
                      count: masks.length,
                      sourceSize: sourceSize,
                      touch: touch,
                    ),
                  ),
                  const SizedBox(width: Sp.s3),
                  Semantics(
                    label: '${masks.length} of ${LocalMask.maxMasks} masks',
                    excludeSemantics: true,
                    child: Text(
                      '${masks.length}/${LocalMask.maxMasks}',
                      style: LumenType.value(touch: touch)
                          .copyWith(color: canAdd ? t.textTertiary : t.warning),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sp.s3),
              if (masks.isEmpty)
                Text(
                  emptyHint,
                  style: LumenType.body(touch: touch)
                      .copyWith(color: t.textSecondary),
                )
              else
                for (final m in masks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sp.s0_5),
                    child: MaskRow(
                      key: ValueKey('mask-row-${m.id}'),
                      assetId: assetId,
                      mask: m,
                      selected: m.id == selected?.id,
                      overlayShown: ui.showOverlay && m.id == selected?.id,
                      canDuplicate: canAdd,
                      touch: touch,
                    ),
                  ),
              if (!canAdd)
                Padding(
                  padding: const EdgeInsets.only(top: Sp.s1),
                  child: Text(
                    AddMaskMenu.fullHint,
                    style: LumenType.caption().copyWith(color: t.textTertiary),
                  ),
                ),
            ],
          ),
        ),
        if (selected != null)
          MaskEditor(
            key: ValueKey('mask-editor-${selected.id}'),
            assetId: assetId,
            mask: selected,
            touch: touch,
          ),
      ],
    );
  }
}
