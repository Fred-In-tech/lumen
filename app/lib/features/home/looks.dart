import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/styles_grid.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/open_editor.dart';
import 'package:lumen/features/projects/project_actions.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Something that gives a whole shoot one look: an AI style (a model
/// edits each photo for its own light) or a preset (the same sliders on
/// every photo).
sealed class Look {
  const Look();
  String get name;
  String get id;
}

final class StyleLook extends Look {
  const StyleLook(this.style);
  final AiStyle style;
  @override
  String get name => style.label;
  @override
  String get id => 'style:${style.id}';
}

final class PresetLook extends Look {
  const PresetLook(this.preset);
  final Preset preset;
  @override
  String get name => preset.name;
  @override
  String get id => 'preset:${preset.id}';
}

const _presetSwatches = [
  [Color(0xFFB9A58C), Color(0xFFEEE3D3)],
  [Color(0xFF6F8796), Color(0xFFD3DEE5)],
  [Color(0xFF8E7C9B), Color(0xFFE6DCEC)],
  [Color(0xFF7E9478), Color(0xFFDDE6D6)],
  [Color(0xFFA77E6E), Color(0xFFF0DBD1)],
];

List<Color> lookSwatch(Look look) => switch (look) {
  StyleLook(:final style) =>
    StylesGrid.swatches[style] ?? const [Color(0xFF8C8C8C), Color(0xFFDDDDDD)],
  PresetLook(:final preset) =>
    _presetSwatches[preset.name.codeUnits.fold(0, (a, b) => a + b) %
        _presetSwatches.length],
};

/// The looks for Home: the user's presets first, then the AI styles.
List<Look> homeLooks(List<Preset> userPresets) => [
  for (final p in userPresets) PresetLook(p),
  for (final s in AiStyle.values) StyleLook(s),
];

/// Applies [look] to a project the user picks (its picks, else every photo
/// that is not rejected), then opens that project.
Future<void> applyLookToProject(
  BuildContext context,
  WidgetRef ref,
  Look look,
) async {
  final (shell, shellRef) = ShellScope.of(context, ref);
  final projects = [
    for (final s in shellRef.read(projectSummariesProvider))
      if (s.deliverable.isNotEmpty) s,
  ];
  if (projects.isEmpty) {
    showToast(context, 'Import a shoot first, then give it a look.');
    return;
  }
  final id = await showChooseProjectDialog(
    context,
    title: 'Use “${look.name}” on…',
    projects: projects,
  );
  if (id == null || !shell.mounted) return;
  final summary = projects.firstWhere((s) => s.project?.id == id);
  final ids = summary.deliverable;
  shellRef.read(shellLocationProvider.notifier).go(ProjectLocation(id));
  switch (look) {
    case StyleLook(:final style):
      final (ok, failed) = await batchAutoEdit(shellRef, ids, style: style);
      if (!shell.mounted) return;
      showToast(
        shell,
        failed == 0
            ? '$ok photos edited with ${style.label}. Every change is a slider.'
            : '$ok edited with ${style.label}, $failed failed.',
        kind: ToastKind.ai,
      );
    case PresetLook(:final preset):
      final n = await applyPresetToAssets(shellRef, preset, ids);
      if (!shell.mounted) return;
      showToast(
        shell,
        '“${preset.name}” applied to $n photos.',
        kind: ToastKind.success,
      );
  }
}

/// Presets are saved from the editor: opens the latest edited photo in
/// Manual mode with Presets showing.
Future<void> createPresetFlow(BuildContext context, WidgetRef ref) async {
  final photo = latestPhoto(ref, editedFirst: true);
  if (photo == null) {
    showToast(
      context,
      'Import a photo first: presets are saved from the editor.',
    );
    return;
  }
  ref.read(presetsOpenProvider(photo.assetId).notifier).set(true);
  showToast(
    context,
    'Set the sliders you like, then choose “Save current as preset”.',
  );
  final scope = [
    for (final e in ref.read(libraryProvider).value ?? const <CatalogEntry>[])
      if (e.projectId == photo.projectId) e.assetId,
  ];
  await openEditor(
    context,
    scope,
    photo.assetId,
    ref: ref,
    mode: EditorMode.manual,
  );
}

/// A look as a card: swatch, name, kind and "Use on a project…".
class LookCard extends ConsumerWidget {
  const LookCard({super.key, required this.look});

  final Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final colors = lookSwatch(look);
    final ai = look is StyleLook;
    final caption = switch (look) {
      StyleLook() => 'Edits each photo for its light',
      PresetLook(:final preset) =>
        '${preset.values.length} '
            '${preset.values.length == 1 ? 'adjustment' : 'adjustments'}',
    };
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        boxShadow: Elevation.e1,
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(Sp.s2),
                  child: _KindChip(ai: ai),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s3, Sp.s3, Sp.s3, Sp.s1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  look.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.heading().copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s2, 0, Sp.s2, Sp.s2),
            child: LumenButton(
              label: 'Use on a project…',
              kind: ButtonKind.ghost,
              height: 30,
              expand: true,
              onPressed: () => applyLookToProject(context, ref, look),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.ai});
  final bool ai;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
      decoration: BoxDecoration(
        color: t.surface1.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ai)
            const AiGlyph(size: 11)
          else
            Icon(
              LucideIcons.slidersHorizontal,
              size: 11,
              color: t.textSecondary,
            ),
          const SizedBox(width: Sp.s1),
          Text(
            ai ? 'AI style' : 'Preset',
            style: LumenType.caption().copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
