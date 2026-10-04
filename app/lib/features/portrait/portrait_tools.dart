import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/backdrop_inputs.dart';
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

/// Background swap (Evoto's Backdrop Changer + background blur): writes
/// `settings.backdrop`. The renderer needs the subject rasters
/// (`BackdropSink.setBackdropInputs`); image mode shows once an image is
/// stored (`imageRef`).
class BackgroundSwapGroup extends ConsumerWidget {
  const BackgroundSwapGroup({super.key, required this.assetId});

  final String assetId;

  static const _swatches = [
    0xFFFFFFFF, 0xFFD9D9D9, 0xFF3A3A3A, 0xFF000000, //
    0xFF2050C0, 0xFF6E8FB5, 0xFFE8D8B0, 0xFF9DB59A, 0xFFE9B9B0,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.settings.backdrop ?? BackdropChange.none),
    );
    final ctl = ref.read(editorProvider(assetId).notifier);
    void commit(BackdropChange next, String label) {
      final s = ref.read(editorProvider(assetId)).value?.settings;
      if (s == null) return;
      ctl.commit(
        s.copyWith(backdrop: next),
        label: label,
        kind: HistoryKind.backdrop,
      );
    }

    Widget slider(
      String label,
      double value,
      double min,
      double max,
      double def,
      BackdropChange Function(double v) apply, {
      bool bipolar = false,
    }) => LumenSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      defaultValue: def,
      bipolar: bipolar,
      onChangeStart: () => ctl.beginGesture(label),
      onChanged: (v) {
        final s = ref.read(editorProvider(assetId)).value?.settings;
        if (s != null) ctl.preview(s.copyWith(backdrop: apply(v)));
      },
      onChangeEnd: () => ctl.commitGesture(
        label: 'Background $label',
        kind: HistoryKind.backdrop,
      ),
      onCommit: (v) => commit(apply(v), 'Background $label ${v.round()}'),
    );

    final modes = {
      BackdropMode.none: 'Off',
      BackdropMode.blur: 'Blur',
      BackdropMode.color: 'Colour',
      BackdropMode.gradient: 'Gradient',
      if (b.imageRef.isNotEmpty) BackdropMode.image: 'Image',
    };
    return DevelopGroup(
      title: 'Background swap',
      modified: b != BackdropChange.none,
      onReset: () => commit(BackdropChange.none, 'Reset background'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Segmented<BackdropMode>(
              value: modes.containsKey(b.mode) ? b.mode : BackdropMode.none,
              options: modes,
              onChanged: (m) =>
                  commit(b.copyWith(mode: m), 'Background ${modes[m]}'),
            ),
          ),
          const SizedBox(height: Sp.s2),
          LumenButton(
            label: b.imageRef.isEmpty ? 'Choose image…' : 'Change image…',
            kind: ButtonKind.ghost,
            icon: const Icon(LucideIcons.image, size: 14),
            onPressed: () => chooseBackdropImage(ref, assetId),
          ),
          if (b.mode == BackdropMode.blur)
            slider('Blur', b.blur, 0, 100, 50, (v) => b.copyWith(blur: v)),
          if (b.mode == BackdropMode.color ||
              b.mode == BackdropMode.gradient ||
              (b.mode == BackdropMode.image && b.fit == BackdropFit.fit))
            _SwatchRow(
              selected: b.color,
              colors: _swatches,
              onPick: (c) => commit(b.copyWith(color: c), 'Background colour'),
            ),
          if (b.mode == BackdropMode.gradient) ...[
            _SwatchRow(
              selected: b.color2,
              colors: _swatches,
              onPick: (c) => commit(b.copyWith(color2: c), 'Gradient colour'),
            ),
            slider('Angle', b.angle, 0, 360, 90, (v) => b.copyWith(angle: v)),
          ],
          if (b.mode == BackdropMode.image)
            Segmented<BackdropFit>(
              value: b.fit,
              options: const {
                BackdropFit.fill: 'Fill',
                BackdropFit.fit: 'Fit',
                BackdropFit.stretch: 'Stretch',
              },
              onChanged: (f) => commit(b.copyWith(fit: f), 'Background fit'),
            ),
          if (b.mode != BackdropMode.none) ...[
            slider(
              'Edge',
              b.edgeShift,
              -100,
              100,
              0,
              (v) => b.copyWith(edgeShift: v),
              bipolar: true,
            ),
            slider('Feather', b.feather, 0, 100, 50, (v) {
              return b.copyWith(feather: v);
            }),
            slider('Remove spill', b.spill, 0, 100, 50, (v) {
              return b.copyWith(spill: v);
            }),
            if (b.mode != BackdropMode.blur)
              slider('Match light', b.match, 0, 100, 0, (v) {
                return b.copyWith(match: v);
              }),
          ],
        ],
      ),
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.selected,
    required this.colors,
    required this.onPick,
  });

  final int selected;
  final List<int> colors;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.s2),
      child: Wrap(
        spacing: Sp.s2,
        runSpacing: Sp.s2,
        children: [
          for (final c in colors)
            Semantics(
              button: true,
              selected: c == selected,
              label: '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPick(c),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c == selected ? t.accent : t.lineStrong,
                      width: c == selected ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
