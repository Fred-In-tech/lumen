import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/lumen_slider.dart';

/// Aspect presets: id → width/height ratio (null = free / original).
const kAspectPresets = <String, double?>{
  'original': null,
  'free': null,
  '1:1': 1,
  '4:5': 4 / 5,
  '3:2': 3 / 2,
  '16:9': 16 / 9,
  '9:16': 9 / 16,
};

/// Fits the largest centered crop of [aspect] (w/h, in pixels) inside an image of [imgAspect].
CropRect centeredCrop(double aspect, double imgAspect) {
  if (aspect >= imgAspect) {
    final h = imgAspect / aspect;
    return CropRect(0, (1 - h) / 2, 1, (1 + h) / 2);
  }
  final w = aspect / imgAspect;
  return CropRect((1 - w) / 2, 0, (1 + w) / 2, 1);
}

/// Geometry controls: aspect, straighten, rotate, flip, reset, done.
class CropPanel extends ConsumerWidget {
  const CropPanel({super.key, required this.assetId, required this.imageAspect, this.touch = false});

  final String assetId;
  final double imageAspect;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final g = ref.watch(editorProvider(assetId).select((s) => s.value?.settings.geometry ?? Geometry.none));
    final ctl = ref.read(editorProvider(assetId).notifier);
    DevelopSettings? cur() => ref.read(editorProvider(assetId)).value?.settings;
    void commit(Geometry next, String label) {
      final s = cur();
      if (s != null) ctl.commit(s.copyWith(geometry: next), label: label, kind: HistoryKind.geometry);
    }

    final oriented = g.swapsAxes ? 1 / imageAspect : imageAspect;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Aspect', style: LumenType.caption().copyWith(color: t.textTertiary)),
      const SizedBox(height: Sp.s1),
      Wrap(spacing: Sp.s1, runSpacing: Sp.s1, children: [
        for (final e in kAspectPresets.entries)
          _Chip(
            label: e.key == 'original' ? 'Original' : (e.key == 'free' ? 'Free' : e.key),
            selected: g.aspect == e.key,
            onTap: () {
              final ratio = e.key == 'original' ? oriented : e.value;
              final crop = ratio == null ? g.crop : centeredCrop(ratio, oriented);
              commit(g.copyWith(aspect: e.key, crop: e.key == 'original' ? CropRect.full : crop), 'Aspect ${e.key}');
            },
          ),
      ]),
      const SizedBox(height: Sp.s3),
      LumenSlider(
        label: 'Straighten',
        value: g.angle,
        min: -Geometry.maxAngle,
        max: Geometry.maxAngle,
        step: 0.1,
        decimals: 1,
        touch: touch,
        onChangeStart: () => ctl.beginGesture('Straighten'),
        onChanged: (v) {
          final s = cur();
          if (s != null) ctl.preview(s.copyWith(geometry: s.geometry.copyWith(angle: v)));
        },
        onChangeEnd: () => ctl.commitGesture(label: 'Straighten', kind: HistoryKind.geometry),
        onCommit: (v) => commit(g.copyWith(angle: v), 'Straighten'),
      ),
      const SizedBox(height: Sp.s2),
      Row(children: [
        LumenIconButton(
          icon: LucideIcons.rotateCcw,
          tooltip: 'Rotate left',
          size: touch ? 44 : 32,
          onPressed: () => commit(g.copyWith(rotate90: g.rotate90 + 3), 'Rotate left'),
        ),
        LumenIconButton(
          icon: LucideIcons.rotateCw,
          tooltip: 'Rotate right',
          size: touch ? 44 : 32,
          onPressed: () => commit(g.copyWith(rotate90: g.rotate90 + 1), 'Rotate right'),
        ),
        LumenIconButton(
          icon: LucideIcons.flipHorizontal2,
          tooltip: 'Flip horizontal',
          size: touch ? 44 : 32,
          onPressed: () => commit(g.copyWith(flipH: !g.flipH), 'Flip horizontal'),
        ),
        LumenIconButton(
          icon: LucideIcons.flipVertical2,
          tooltip: 'Flip vertical',
          size: touch ? 44 : 32,
          onPressed: () => commit(g.copyWith(flipV: !g.flipV), 'Flip vertical'),
        ),
      ]),
      const SizedBox(height: Sp.s4),
      Row(children: [
        LumenButton(label: 'Reset', kind: ButtonKind.ghost, onPressed: () => commit(Geometry.none, 'Reset crop')),
        const Spacer(),
        LumenButton(label: 'Done', kind: ButtonKind.primary, onPressed: () => ctl.setCropMode(false)),
      ]),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.accentTint : t.surface2,
            borderRadius: BorderRadius.circular(Rad.pill),
            border: Border.all(color: selected ? t.accent : t.lineStrong),
          ),
          child: Text(label, style: LumenType.label().copyWith(color: selected ? t.accent : t.textSecondary)),
        ),
      ),
    );
  }
}
