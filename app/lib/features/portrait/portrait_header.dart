import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/auto_retouch.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/segmented.dart';

class PortraitFaceStatus extends ConsumerWidget {
  const PortraitFaceStatus({
    super.key,
    required this.assetId,
    required this.status,
    required this.showFaces,
  });

  final String assetId;
  final AsyncValue<FaceAnalysis?> status;
  final bool showFaces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final count = status.value?.faces.length;
    final text = switch (count) {
      null when status.hasError => 'Face detection isn’t available here. Masks and manual tools still work.',
      null => 'Detecting faces…',
      0 => 'No faces found. Retouch applies when a face is visible.',
      1 => '1 face. Click it to edit this person only.',
      _ => '$count faces. Click a face to edit one person.',
    };
    return Row(
      children: [
        Icon(LucideIcons.scanFace, size: 16, color: t.textSecondary),
        const SizedBox(width: Sp.s2),
        Expanded(
          child: Text(
            text,
            style: LumenType.body().copyWith(color: t.textSecondary),
          ),
        ),
        if ((count ?? 0) > 0)
          LumenIconButton(
            icon: showFaces ? LucideIcons.eye : LucideIcons.eyeOff,
            tooltip: showFaces ? 'Hide face boxes' : 'Show face boxes',
            onPressed: () => ref
                .read(portraitUiProvider(assetId).notifier)
                .setShowFaces(!showFaces),
          ),
      ],
    );
  }
}

class PortraitTargetTabs extends ConsumerWidget {
  const PortraitTargetTabs({
    super.key,
    required this.assetId,
    required this.ui,
  });

  final String assetId;
  final PortraitUiState ui;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(portraitUiProvider(assetId).notifier);
    final options = <String, String>{
      for (final g in FaceGroup.values) g.name: g.label,
      if (ui.selectedFaceId != null) _individualKey: 'Individual',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Segmented<String>(
        value: ui.target.isPerson ? _individualKey : ui.target.group.name,
        options: options,
        onChanged: (key) {
          if (key == _individualKey) return;
          notifier.selectGroup(FaceGroup.fromName(key));
        },
      ),
    );
  }
}

class AutoRetouchButton extends ConsumerStatefulWidget {
  const AutoRetouchButton({super.key, required this.assetId, this.height = 40});

  final String assetId;
  final double height;

  @override
  ConsumerState<AutoRetouchButton> createState() => _AutoRetouchState();
}

/// Lets the user correct the selected face's retouch group (Evoto's gender /
/// age chips). Stored in the local face cache only.
class FaceTagRow extends ConsumerWidget {
  const FaceTagRow({super.key, required this.assetId, required this.face});

  final String assetId;
  final DetectedFace face;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Row(
      children: [
        Text(
          'Tag as',
          style: LumenType.caption().copyWith(color: t.textTertiary),
        ),
        const SizedBox(width: Sp.s2),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Segmented<FaceGroup>(
              value: face.group,
              options: {
                for (final g in FaceGroup.values)
                  g: g == FaceGroup.all ? 'None' : g.label,
              },
              onChanged: (g) => tagFace(ref, assetId, face, g),
            ),
          ),
        ),
      ],
    );
  }
}

/// Background works on the whole photo (not per face) and only on plain
/// backdrops: says so, plus why it is off when the engine disabled it.
class BackdropNote extends ConsumerWidget {
  const BackdropNote({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final reason = ref.watch(backdropStatusProvider(assetId))?.reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s2),
      child: Text(
        reason ?? 'Applies to the whole photo. Works best on plain backdrops.',
        style: LumenType.caption().copyWith(
          color: reason == null ? t.textTertiary : t.warning,
        ),
      ),
    );
  }
}

const _individualKey = 'individual';

/// Need-scaled Auto Retouch: measures every face (skin, blemishes, eyes,
/// teeth, lines) and sets values to match, never touching values set by
/// hand. Falls back to the static natural recipe when faces cannot be
/// measured.
class _AutoRetouchState extends ConsumerState<AutoRetouchButton> {
  bool _busy = false;

  Future<void> _run() async {
    final id = widget.assetId;
    final doc = ref.read(editorProvider(id)).value?.doc;
    if (doc == null) return;
    // Measure only once faces are known (the panel's analysis found them);
    // otherwise the static recipe applies right away.
    final faces = ref.read(portraitFacesProvider(id));
    setState(() => _busy = true);
    try {
      final RetouchNeeds? needs;
      if (faces == null || faces.faces.isEmpty) {
        needs = null;
      } else {
        needs =
            (await ref
                    .read(autoRetouchPlannerProvider)
                    .measure(id, doc.settings))
                .needs;
      }
      final now = ref.read(editorProvider(id)).value;
      if (now == null) return;
      ref
          .read(editorProvider(id).notifier)
          .commit(
            now.settings.copyWith(
              portrait: PortraitPresets.autoRetouchFor(
                now.settings.portrait,
                needs,
                locked: manualPortraitLocks(now.doc.history),
              ),
            ),
            label: 'Auto Retouch',
            kind: HistoryKind.preset,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LumenButton(
    label: _busy ? 'Measuring faces…' : 'Auto Retouch',
    kind: ButtonKind.ai,
    expand: true,
    height: widget.height,
    icon: const AiGlyph(size: 16, neutral: true),
    tooltip: 'Skin, eyes and teeth retouch scaled to what each face needs',
    onPressed: _busy ? null : _run,
  );
}

/// Clothing works on the whole photo through the clothes mask: says so, plus
/// why it is off when no clothes were found.
class ClothesNote extends ConsumerWidget {
  const ClothesNote({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final reason = ref.watch(clothesStatusProvider(assetId))?.reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s2),
      child: Text(
        reason ?? 'Smooths fabric folds and removes lint on every outfit.',
        style: LumenType.caption().copyWith(
          color: reason == null ? t.textTertiary : t.warning,
        ),
      ),
    );
  }
}
