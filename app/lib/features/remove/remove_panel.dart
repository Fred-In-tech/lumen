import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart' show SubGroupLabel;
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/remove/ai_remover.dart';
import 'package:lumen/features/remove/heal_op_row.dart';
import 'package:lumen/features/remove/remove_status_card.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen/widgets/segmented.dart';

/// The Remove module: Remove / Heal / Clone tools, brush size, AI fill,
/// the running status and the list of fixes (newest first). Strokes are
/// painted on the canvas (`RemoveCanvas`).
class RemovePanel extends ConsumerStatefulWidget {
  const RemovePanel({super.key, required this.assetId, this.touch = false});

  final String assetId;
  final bool touch;

  static const emptyHint =
      'Paint over a distraction to remove it, or heal and clone to fix '
      'blemishes. Every fix is listed here and stays editable.';

  @override
  ConsumerState<RemovePanel> createState() => _RemovePanelState();
}

class _RemovePanelState extends ConsumerState<RemovePanel> {
  @override
  void initState() {
    super.initState();
    // A previous (approved) AI remover download loads in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(aiRemoverProvider.notifier).probe());
    });
  }

  String _toolHint(RemoveUiState ui) {
    final touch = widget.touch;
    return switch (ui.tool) {
      RemoveTool.remove => 'Paint over what you want gone, then let go.',
      RemoveTool.heal =>
        touch
            ? 'Paint over a blemish. Texture comes from nearby, or from '
                  'the source you set.'
            : 'Paint over a blemish. Texture comes from nearby; '
                  'Alt-click (Option-click) to choose it.',
      RemoveTool.clone =>
        touch
            ? 'Set the source, tap the photo where to copy from, then paint.'
            : 'Alt-click (Option-click) where to copy from, then paint.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final id = widget.assetId;
    final touch = widget.touch;
    // Kick off (or reuse) the face analysis so the face warning can apply.
    ref.watch(portraitFacesStatusProvider(id));
    final ui = ref.watch(removeUiProvider(id));
    final uiCtl = ref.read(removeUiProvider(id).notifier);
    final ops = ref.watch(
      editorProvider(id).select((s) => s.value?.settings.heal ?? const []),
    );
    final pad = touch ? 0.0 : Sp.s4;
    final hint = LumenType.body(touch: touch).copyWith(color: t.textSecondary);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, Sp.s2, pad, Sp.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Segmented<RemoveTool>(
              value: ui.tool,
              height: touch ? 36 : 26,
              options: {for (final tool in RemoveTool.values) tool: tool.label},
              onChanged: uiCtl.setTool,
            ),
          ),
          const SizedBox(height: Sp.s2),
          Text(_toolHint(ui), style: hint),
          if (ui.tool.usesSource) ...[
            const SizedBox(height: Sp.s2),
            _SourceRow(assetId: id, ui: ui, touch: touch),
          ],
          const SizedBox(height: Sp.s2),
          LumenSlider(
            label: 'Size',
            value: ui.size,
            min: RemoveUiState.minSize,
            max: RemoveUiState.maxSize,
            defaultValue: RemoveUiState.defaultSize,
            bipolar: false,
            touch: touch,
            onChanged: uiCtl.setSize,
            onCommit: uiCtl.setSize,
          ),
          if (ui.tool == RemoveTool.remove) ...[
            const SizedBox(height: Sp.s3),
            AiFillRow(touch: touch),
          ],
          const SizedBox(height: Sp.s2),
          RemoveStatusCard(assetId: id, touch: touch),
          const SubGroupLabel('Fixes'),
          if (ops.isEmpty)
            Text(RemovePanel.emptyHint, style: hint)
          else
            for (final op in ops.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.s0_5),
                child: HealOpRow(
                  key: ValueKey('heal-op-${op.id}'),
                  assetId: id,
                  op: op,
                  all: ops,
                  touch: touch,
                ),
              ),
        ],
      ),
    );
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({
    required this.assetId,
    required this.ui,
    this.touch = false,
  });

  final String assetId;
  final RemoveUiState ui;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ctl = ref.read(removeUiProvider(assetId).notifier);
    final label = ui.pickingSource
        ? 'Tap the photo to choose the source'
        : ui.source != null
        ? 'Source set'
        : ui.tool == RemoveTool.heal
        ? 'Source: automatic'
        : 'No source yet';
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: LumenType.label(touch: touch)
                .copyWith(color: ui.pickingSource ? t.accent : t.textPrimary),
          ),
        ),
        LumenButton(
          label: 'Set source',
          kind: ButtonKind.ghost,
          height: touch ? 44 : 28,
          onPressed: ctl.startPickingSource,
        ),
        if (ui.source != null && ui.tool == RemoveTool.heal)
          LumenButton(
            label: 'Auto',
            kind: ButtonKind.ghost,
            height: touch ? 44 : 28,
            tooltip: 'Pick the texture automatically',
            onPressed: ctl.clearSource,
          ),
      ],
    );
  }
}
