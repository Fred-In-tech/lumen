import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/looks/look.dart';
import 'package:lumen/features/looks/look_details.dart';
import 'package:lumen/features/looks/look_previews.dart';
import 'package:lumen/features/looks/look_sample.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

export 'package:lumen/features/looks/look.dart';

/// The looks for Home: the user's presets and LUTs (newest first), then
/// the AI styles.
List<Look> homeLooks(List<Preset> userPresets) {
  final mine =
      [
        for (final p in userPresets)
          if (!p.builtIn) p,
      ]..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
  return [
    for (final p in mine) PresetLook(p),
    for (final s in AiStyle.values) StyleLook(s),
  ];
}

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

/// A look as a card: a real image sample (hold to compare), its type and
/// source, and "Use on a project…". Imported and saved looks have a "…"
/// menu (details, rename, delete).
class LookCard extends ConsumerWidget {
  const LookCard({super.key, required this.look});

  final Look look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final photo = ref.watch(homePreviewPhotoProvider);
    final look = this.look;
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                LookSample(
                  look: look,
                  photo: photo.value,
                  waiting: photo.isLoading,
                ),
                Positioned(
                  left: Sp.s2,
                  top: Sp.s2,
                  child: LookKindChip(kind: look.kind),
                ),
                if (look is PresetLook && look.editable)
                  Positioned(
                    right: Sp.s1,
                    top: Sp.s1,
                    child: _LookMenuButton(look: look),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s3, Sp.s3, Sp.s3, Sp.s1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  look.kind == LookKind.lut ? 'LUT: ${look.name}' : look.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.heading().copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  look.sourceLabel,
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

/// The type badge: Look (AI), Preset or LUT.
class LookKindChip extends StatelessWidget {
  const LookKindChip({super.key, required this.kind});
  final LookKind kind;

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
          switch (kind) {
            LookKind.look => const AiGlyph(size: 11),
            LookKind.preset => Icon(
              LucideIcons.slidersHorizontal,
              size: 11,
              color: t.textSecondary,
            ),
            LookKind.lut => Icon(
              LucideIcons.swatchBook,
              size: 11,
              color: t.textSecondary,
            ),
          },
          const SizedBox(width: Sp.s1),
          Text(
            kind.label,
            style: LumenType.caption().copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LookMenuButton extends ConsumerWidget {
  const _LookMenuButton({required this.look});
  final PresetLook look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Material(
      color: t.surface1.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkResponse(
        radius: 16,
        onTapDown: (d) => showLookMenu(context, ref, look, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Semantics(
            label: 'More for ${look.name}',
            button: true,
            child: Icon(LucideIcons.ellipsis, size: 14, color: t.textSecondary),
          ),
        ),
      ),
    );
  }
}

enum _LookAction { details, rename, delete }

/// Details (the import report), Rename, Delete for a user or imported look.
Future<void> showLookMenu(
  BuildContext context,
  WidgetRef ref,
  PresetLook look,
  Offset at,
) async {
  final t = context.tokens;
  PopupMenuItem<_LookAction> item(
    _LookAction a,
    IconData icon,
    String label, {
    bool danger = false,
  }) => PopupMenuItem(
    value: a,
    height: 36,
    child: Row(
      children: [
        Icon(icon, size: 14, color: danger ? t.danger : t.textSecondary),
        const SizedBox(width: Sp.s2),
        Text(
          label,
          style: LumenType.body().copyWith(
            color: danger ? t.danger : t.textPrimary,
          ),
        ),
      ],
    ),
  );
  final action = await showMenu<_LookAction>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    color: t.surface1,
    items: [
      item(_LookAction.details, LucideIcons.info, 'Details'),
      item(_LookAction.rename, LucideIcons.pencil, 'Rename'),
      const PopupMenuDivider(height: 8),
      item(_LookAction.delete, LucideIcons.trash2, 'Delete', danger: true),
    ],
  );
  if (action == null || !context.mounted) return;
  final presets = ref.read(userPresetsProvider.notifier);
  switch (action) {
    case _LookAction.details:
      await showLookDetails(context, look.preset);
    case _LookAction.rename:
      final name = await showProjectNameDialog(
        context,
        title: 'Rename look',
        action: 'Rename',
        initial: look.name,
      );
      if (name != null && name.trim().isNotEmpty) {
        await presets.rename(look.preset.id, name);
      }
    case _LookAction.delete:
      await presets.remove(look.preset.id);
      if (context.mounted) {
        showToast(context, '“${look.name}” deleted. Edited photos keep it.');
      }
  }
}
