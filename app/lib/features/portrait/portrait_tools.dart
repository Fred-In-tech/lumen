import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/liquify_canvas.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen/widgets/segmented.dart';

/// A UI-only slider (brush settings), not a document param.
Widget portraitBrushSlider(
  String label,
  double value,
  double min,
  double max,
  double def,
  ValueChanged<double> set, {
  int decimals = 0,
}) => LumenSlider(
  label: label,
  value: value,
  min: min,
  max: max,
  defaultValue: def,
  bipolar: false,
  step: decimals > 0 ? 0.5 : 1,
  decimals: decimals,
  onChanged: set,
  onCommit: set,
);

/// Skin pen (Manual Tuning Pen): paint or erase where skin retouch applies.
class SkinPenRow extends ConsumerWidget {
  const SkinPenRow({
    super.key,
    required this.assetId,
    required this.ui,
    required this.portrait,
  });

  final String assetId;
  final PortraitUiState ui;
  final PortraitSettings portrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final n = ref.read(portraitUiProvider(assetId).notifier);
    final active = ui.tool == PortraitCanvasTool.pen;
    final count = portrait.skinPen.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  count == 0
                      ? 'Skin pen: paint or erase where skin retouch applies.'
                      : 'Skin pen: $count stroke${count == 1 ? '' : 's'}',
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
              ),
              if (count > 0)
                LumenIconButton(
                  icon: LucideIcons.rotateCcw,
                  tooltip: 'Clear skin pen',
                  onPressed: () {
                    final s = ref.read(editorProvider(assetId)).value?.settings;
                    if (s == null) return;
                    ref
                        .read(editorProvider(assetId).notifier)
                        .commit(
                          s.copyWith(
                            portrait: s.portrait.withSkinPen(const []),
                          ),
                          label: 'Clear skin pen',
                          kind: HistoryKind.reset,
                        );
                  },
                ),
              LumenButton(
                label: active ? 'Done' : 'Skin pen',
                kind: active ? ButtonKind.primary : ButtonKind.secondary,
                height: 28,
                onPressed: () => n.toggleTool(PortraitCanvasTool.pen),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: Sp.s2),
            Segmented<bool>(
              value: ui.penErase,
              options: const {false: 'Paint', true: 'Erase'},
              onChanged: (v) => n.setPen(erase: v),
            ),
            portraitBrushSlider(
              'Size',
              ui.penRadius * 100,
              0.5,
              15,
              2.5,
              (v) => n.setPen(radius: v / 100),
              decimals: 1,
            ),
            portraitBrushSlider(
              'Hardness',
              ui.penHardness * 100,
              0,
              100,
              50,
              (v) => n.setPen(hardness: v / 100),
            ),
            portraitBrushSlider(
              'Flow',
              ui.penFlow * 100,
              1,
              100,
              100,
              (v) => n.setPen(flow: v / 100),
            ),
          ],
        ],
      ),
    );
  }
}

/// Liquify: brush tools that bend the photo (Evoto's manual Liquify).
class LiquifyGroup extends ConsumerWidget {
  const LiquifyGroup({super.key, required this.assetId, required this.ui});

  final String assetId;
  final PortraitUiState ui;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(portraitUiProvider(assetId).notifier);
    final strokes = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.settings.liquify.length ?? 0),
    );
    final active = ui.tool == PortraitCanvasTool.liquify;
    return DevelopGroup(
      title: 'Liquify',
      modified: strokes > 0,
      onReset: () {
        final s = ref.read(editorProvider(assetId)).value?.settings;
        if (s == null) return;
        ref
            .read(editorProvider(assetId).notifier)
            .commit(
              s.copyWith(liquify: const []),
              label: 'Reset liquify',
              kind: HistoryKind.reset,
            );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Segmented<LiquifyTool>(
              value: ui.liquifyTool,
              options: {for (final t in LiquifyTool.values) t: liquifyLabel(t)},
              onChanged: (t) {
                n.setLiquify(tool: t);
                n.setTool(PortraitCanvasTool.liquify);
              },
            ),
          ),
          portraitBrushSlider(
            'Size',
            ui.liquifyRadius * 100,
            1,
            30,
            6,
            (v) => n.setLiquify(radius: v / 100),
            decimals: 1,
          ),
          portraitBrushSlider(
            'Strength',
            ui.liquifyStrength * 100,
            1,
            100,
            50,
            (v) => n.setLiquify(strength: v / 100),
          ),
          const SizedBox(height: Sp.s2),
          LumenButton(
            label: active ? 'Done' : 'Liquify brush',
            kind: active ? ButtonKind.primary : ButtonKind.secondary,
            expand: true,
            onPressed: () => n.toggleTool(PortraitCanvasTool.liquify),
          ),
        ],
      ),
    );
  }
}
