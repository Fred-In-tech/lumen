import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/projects/progress_stepper.dart';
import 'package:lumen/features/projects/project_actions.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/drop_claim.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/thumb_image.dart';

/// What a project's context menu can do.
enum ProjectMenuAction { open, rename, cover, delete }

/// The project context menu items (card "…" button and right-click).
List<PopupMenuEntry<ProjectMenuAction>> projectMenuItems(
  BuildContext context, {
  bool includeOpen = true,
}) {
  final t = context.tokens;
  PopupMenuItem<ProjectMenuAction> item(
    ProjectMenuAction a,
    IconData icon,
    String label, {
    bool danger = false,
  }) => PopupMenuItem(
    value: a,
    height: 36,
    child: Row(
      children: [
        Icon(icon, size: 16, color: danger ? t.danger : t.textSecondary),
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
  return [
    if (includeOpen)
      item(ProjectMenuAction.open, LucideIcons.folderOpen, 'Open'),
    item(ProjectMenuAction.rename, LucideIcons.pencil, 'Rename…'),
    item(ProjectMenuAction.cover, LucideIcons.image, 'Set cover…'),
    const PopupMenuDivider(height: 8),
    item(ProjectMenuAction.delete, LucideIcons.trash2, 'Delete…', danger: true),
  ];
}

/// Runs a context-menu [action] on [summary].
Future<void> runProjectMenuAction(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary summary,
  ProjectMenuAction action,
) async {
  final project = summary.project;
  if (project == null) return;
  switch (action) {
    case ProjectMenuAction.open:
      openProject(ref, project.id);
    case ProjectMenuAction.rename:
      await renameProjectFlow(context, ref, project);
    case ProjectMenuAction.cover:
      await setCoverFlow(context, ref, summary);
    case ProjectMenuAction.delete:
      await deleteProjectFlow(context, ref, summary);
  }
}

/// A project as a card: cover mosaic, name, date and count, the five-step
/// progress and the next step as a button. Accepts dropped photos.
class ProjectCard extends ConsumerStatefulWidget {
  const ProjectCard({super.key, required this.summary});

  final ProjectSummary summary;

  @override
  ConsumerState<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<ProjectCard> {
  bool _dropping = false;

  Future<void> _menuAt(Offset global) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<ProjectMenuAction>(
      context: context,
      color: context.tokens.surface1,
      position: RelativeRect.fromRect(
        global & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: projectMenuItems(context),
    );
    if (action != null && mounted) {
      await runProjectMenuAction(context, ref, widget.summary, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.summary;
    final p = s.project;
    final next = s.progress.next;
    final date = p == null ? null : formatShootDate(p.displayDate);
    final count = '${s.count} ${s.count == 1 ? 'photo' : 'photos'}';
    Widget card = Pressable(
      onTap: () => openProject(ref, p?.id),
      semanticLabel: 'Project ${s.name}, $count',
      scaleOnPress: false,
      radius: Rad.lg,
      builder: (context, states) {
        final hover = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          transform: Matrix4.translationValues(0, hover ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(Rad.lg),
            boxShadow: hover || _dropping ? Elevation.e2 : Elevation.e1,
            border: Border.all(
              color: _dropping ? t.accent : t.line,
              width: _dropping ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _CoverMosaic(summary: s, dropping: _dropping),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s3, Sp.s2, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LumenType.heading().copyWith(
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            date == null ? count : '$date  ·  $count',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LumenType.caption().copyWith(
                              color: t.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (p != null)
                      _MoreButton(
                        onSelected: (a) =>
                            runProjectMenuAction(context, ref, s, a),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.s2, Sp.s3, Sp.s2, 0),
                child: ProgressStepper(progress: s.progress),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s3, Sp.s4, Sp.s4),
                child: LumenButton(
                  label: next.step == null ? 'Open project' : next.label,
                  icon: Icon(
                    next.step == null
                        ? LucideIcons.circleCheck
                        : LucideIcons.arrowRight,
                  ),
                  kind: next.step == null
                      ? ButtonKind.ghost
                      : ButtonKind.secondary,
                  expand: true,
                  onPressed: () => runNextStep(context, ref, s),
                ),
              ),
            ],
          ),
        );
      },
    );
    card = GestureDetector(
      onSecondaryTapUp: p == null ? null : (d) => _menuAt(d.globalPosition),
      onLongPressStart: p == null ? null : (d) => _menuAt(d.globalPosition),
      child: card,
    );
    if (ref.watch(platformInfoProvider).supportsDragAndDrop) {
      card = DropTarget(
        onDragEntered: (_) => setState(() => _dropping = true),
        onDragExited: (_) => setState(() => _dropping = false),
        onDragDone: (details) async {
          DropClaim.claim();
          setState(() => _dropping = false);
          final (shell, shellRef) = ShellScope.of(context, ref);
          final files = await readXFiles(details.files);
          if (!shell.mounted) return;
          unawaited(importInto(shell, shellRef, p?.id, files: files));
        },
        child: card,
      );
    }
    return card;
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onSelected});

  final ValueChanged<ProjectMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopupMenuButton<ProjectMenuAction>(
      tooltip: 'Project actions',
      color: t.surface1,
      padding: EdgeInsets.zero,
      icon: Icon(LucideIcons.ellipsis, size: 18, color: t.textSecondary),
      onSelected: onSelected,
      itemBuilder: projectMenuItems,
    );
  }
}

/// One large cover with two smaller photos beside it; an empty project
/// invites a drop.
class _CoverMosaic extends StatelessWidget {
  const _CoverMosaic({required this.summary, required this.dropping});

  final ProjectSummary summary;
  final bool dropping;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final strip = summary.strip(3);
    if (strip.isEmpty || dropping) {
      return ColoredBox(
        color: dropping ? t.accentTint : t.surface2,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.imagePlus,
                size: 22,
                color: dropping ? t.accent : t.textTertiary,
              ),
              const SizedBox(height: Sp.s1_5),
              Text(
                dropping ? 'Drop to add here' : 'No photos yet',
                style: LumenType.caption().copyWith(
                  color: dropping ? t.accent : t.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    Widget thumb(CatalogEntry e) =>
        ThumbImage(key: ValueKey(e.assetId), entry: e);
    if (strip.length < 3) return SizedBox.expand(child: thumb(strip.first));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 2, child: thumb(strip[0])),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: thumb(strip[1])),
              const SizedBox(height: 2),
              Expanded(child: thumb(strip[2])),
            ],
          ),
        ),
      ],
    );
  }
}
