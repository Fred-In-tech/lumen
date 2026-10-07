import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/library/photo_browser.dart';
import 'package:lumen/features/projects/progress_stepper.dart';
import 'package:lumen/features/projects/project_actions.dart';
import 'package:lumen/features/projects/project_card.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/page_header.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/buttons.dart';

/// One project (or, with a null [projectId], the Unsorted photos): the
/// breadcrumb, the five-step progress with the next step, project actions
/// and the photo grid scoped to the project.
class ProjectPage extends ConsumerWidget {
  const ProjectPage({super.key, required this.projectId});

  final String? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(projectSummaryProvider(projectId));
    final nav = ref.read(shellLocationProvider.notifier);
    if (summary == null) {
      return _Gone(onBack: () => nav.go(const ProjectsLocation()));
    }
    final (shell, shellRef) = ShellScope.of(context, ref);
    final p = summary.project;
    final n = summary.count;
    final count = '$n ${n == 1 ? 'photo' : 'photos'}';
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    final deliverable = summary.deliverable.length;
    final hasPicks = summary.photos.any((e) => e.flag == PhotoFlag.pick);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: summary.name,
          breadcrumb: [
            (label: 'Home', onTap: () => nav.go(const HomeLocation())),
            (label: 'Projects', onTap: () => nav.go(const ProjectsLocation())),
            (label: summary.name, onTap: null),
          ],
          subtitle: p == null
              ? 'Photos that are not in a project  ·  $count'
              : '${formatShootDate(p.displayDate)}  ·  $count',
          trailingTitle: p == null
              ? null
              : PopupMenuButton<ProjectMenuAction>(
                  tooltip: 'Project actions',
                  color: context.tokens.surface1,
                  icon: Icon(
                    LucideIcons.ellipsis,
                    size: 20,
                    color: context.tokens.textSecondary,
                  ),
                  onSelected: (a) =>
                      runProjectMenuAction(context, ref, summary, a),
                  itemBuilder: (context) =>
                      projectMenuItems(context, includeOpen: false),
                ),
          actions: [
            LumenButton(
              label: 'Add photos',
              icon: const Icon(LucideIcons.imagePlus),
              onPressed: () => importInto(shell, shellRef, projectId),
            ),
            LumenButton(
              label: hasPicks ? 'Export picks' : 'Export all',
              icon: const Icon(LucideIcons.share),
              kind: ButtonKind.primary,
              tooltip: deliverable == 0
                  ? 'Nothing to export yet'
                  : 'Export $deliverable with a preset',
              onPressed: deliverable == 0
                  ? null
                  : () => exportDeliverables(context, ref, summary),
            ),
          ],
        ),
        if (p != null && n > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(
              phone ? Sp.s4 : Sp.s8,
              0,
              phone ? Sp.s4 : Sp.s8,
              Sp.s4,
            ),
            child: _ProgressPanel(summary: summary, phone: phone),
          ),
        Expanded(
          child: PhotoBrowser(
            entries: summary.photos,
            onDropFiles: (files) =>
                importInto(shell, shellRef, projectId, files: files),
            empty: (dragging) => _EmptyProject(
              dragging: dragging,
              onAdd: () => importInto(shell, shellRef, projectId),
              dropSupported: ref
                  .watch(platformInfoProvider)
                  .supportsDragAndDrop,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressPanel extends ConsumerWidget {
  const _ProgressPanel({required this.summary, required this.phone});

  final ProjectSummary summary;
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final next = summary.progress.next;
    final button = LumenButton(
      label: next.step == null ? 'All delivered' : next.label,
      icon: Icon(
        next.step == null ? LucideIcons.circleCheck : LucideIcons.arrowRight,
      ),
      kind: next.step == null ? ButtonKind.ghost : ButtonKind.primary,
      onPressed: next.step == null
          ? null
          : () => runNextStep(context, ref, summary),
    );
    final stepper = ProgressStepper(
      progress: summary.progress,
      detailed: !phone,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.s3, Sp.s4, Sp.s4, Sp.s4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        boxShadow: Elevation.e1,
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stepper,
                const SizedBox(height: Sp.s4),
                button,
              ],
            )
          : Row(
              children: [
                Expanded(child: stepper),
                const SizedBox(width: Sp.s6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      next.step == null ? 'Shoot complete' : 'Next step',
                      style: LumenType.caption().copyWith(
                        color: t.textTertiary,
                      ),
                    ),
                    const SizedBox(height: Sp.s1_5),
                    button,
                  ],
                ),
              ],
            ),
    );
  }
}

class _EmptyProject extends StatelessWidget {
  const _EmptyProject({
    required this.dragging,
    required this.onAdd,
    required this.dropSupported,
  });

  final bool dragging;
  final bool dropSupported;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: phone ? Sp.s4 : Sp.s8,
        vertical: Sp.s2,
      ),
      child: AnimatedContainer(
        duration: Motion.fast,
        height: 260,
        decoration: BoxDecoration(
          color: dragging ? t.accentTint : t.surface1,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(
            color: dragging ? t.accent : t.lineStrong,
            width: dragging ? 2 : 1,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.imagePlus,
                size: 28,
                color: dragging ? t.accent : t.textSecondary,
              ),
              const SizedBox(height: Sp.s3),
              Text(
                dragging
                    ? 'Drop to add to this project'
                    : 'Add the photos of this shoot',
                style: LumenType.titleSerif().copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: Sp.s1),
              Text(
                dropSupported
                    ? 'Drop files or a folder here, or choose them.'
                    : 'Choose them from your photos.',
                style: LumenType.body().copyWith(color: t.textTertiary),
              ),
              const SizedBox(height: Sp.s5),
              LumenButton(
                label: 'Add photos',
                kind: ButtonKind.primary,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This project no longer exists.',
            style: LumenType.body().copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: Sp.s3),
          LumenButton(label: 'All projects', onPressed: onBack),
        ],
      ),
    );
  }
}
