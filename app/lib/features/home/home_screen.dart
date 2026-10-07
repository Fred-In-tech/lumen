import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/cull/cull_bar.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/open_editor.dart';
import 'package:lumen/features/home/hero_carousel.dart';
import 'package:lumen/features/home/hero_visuals.dart';
import 'package:lumen/features/home/home_sidebar.dart';
import 'package:lumen/features/home/looks.dart';
import 'package:lumen/features/library/empty_library.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/looks/looks_drop_zone.dart';
import 'package:lumen/features/projects/project_actions.dart';
import 'package:lumen/features/projects/project_card.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/drop_claim.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/dashed_card.dart';

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// "Tuesday 7 October".
String homeDateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// Projects for the Home row: unfinished first (most recent activity
/// first), then finished ones, then the Unsorted photos.
List<ProjectSummary> homeProjects(
  List<ProjectSummary> projects,
  ProjectSummary? unsorted, {
  int max = 8,
}) => [
  ...projects.where((s) => !s.progress.isComplete),
  ...projects.where((s) => s.progress.isComplete),
].take(max).followedBy([?unsorted]).toList();

/// The app's front page: what to do next across your shoots.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _dragging = false;

  List<HeroSlide> _slides(BuildContext shell, WidgetRef shellRef) => [
    HeroSlide(
      eyebrow: 'Camera RAW',
      headline: 'Edit RAW with 32-bit precision.',
      body:
          'Your RAW file stays untouched. Edits run on 32-bit float pixels, '
          'so skies, skin and shadows keep their smooth gradients.',
      action: 'Import RAW photos',
      onAction: () => pickAndImport(shell, shellRef),
      visual: (t) => RawVisualPainter(ink: t.textPrimary, accent: t.accent),
    ),
    HeroSlide(
      eyebrow: 'Auto Retouch',
      ai: true,
      headline: 'Auto Retouch that keeps skin texture.',
      body:
          'Blemishes, under-eye shadows and shine are measured face by face '
          'and corrected locally. Pores and freckles stay. Every change is '
          'a slider you can move back.',
      action: 'Retouch a portrait',
      onAction: _retouchLatest,
      visual: (t) => SkinVisualPainter(line: t.line),
    ),
    HeroSlide(
      eyebrow: 'Smart Cull',
      ai: true,
      headline: 'Cull a whole shoot in one pass.',
      body:
          'Smart Cull flags closed eyes, blur and near-duplicates, then '
          'suggests picks and rejects for you to review and accept.',
      action: 'Cull a shoot',
      onAction: () => _cullLatest(shell, shellRef),
      visual: (t) => CullVisualPainter(
        pick: t.success,
        reject: t.danger,
        paper: t.surface1,
      ),
    ),
  ];

  Future<void> _retouchLatest() async {
    final (shell, shellRef) = ShellScope.of(context, ref);
    final photo = latestPhoto(ref);
    if (photo == null) return pickAndImport(shell, shellRef);
    final scope = [
      for (final e in ref.read(libraryProvider).value ?? const <CatalogEntry>[])
        if (e.projectId == photo.projectId) e.assetId,
    ];
    await openEditor(
      context,
      scope,
      photo.assetId,
      ref: ref,
      mode: EditorMode.auto,
    );
  }

  Future<void> _cullLatest(BuildContext shell, WidgetRef shellRef) async {
    final withPhotos = [
      for (final s in ref.read(projectSummariesProvider))
        if (s.count > 0) s,
    ];
    if (withPhotos.isEmpty) return pickAndImport(shell, shellRef);
    final target = withPhotos.firstWhere(
      (s) => !s.progress.of(ProjectStep.cull).isComplete,
      orElse: () => withPhotos.first,
    );
    shellRef
        .read(shellLocationProvider.notifier)
        .go(ProjectLocation(target.project?.id));
    await runSmartCull(shell, shellRef, target.photos);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (shell, shellRef) = ShellScope.of(context, ref);
    final entries = ref.watch(libraryProvider).value ?? const <CatalogEntry>[];
    final summaries = ref.watch(projectSummariesProvider);
    final unsorted = ref.watch(unsortedSummaryProvider);
    final presets = ref.watch(userPresetsProvider).value ?? const <Preset>[];
    final isNew = entries.isEmpty && summaries.isEmpty;
    final screen = MediaQuery.sizeOf(context).width;
    final phone = screen < Layout.phoneBreakpoint;
    final pad = phone ? Sp.s4 : Sp.s8;

    Widget body = LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1080;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopRow(
              showGreeting: !wide,
              onImport: () => pickAndImport(shell, shellRef),
            ),
            SizedBox(height: phone ? Sp.s4 : Sp.s5),
            if (isNew)
              _WelcomeCard(
                dragging: _dragging,
                onChoose: () => pickAndImport(shell, shellRef),
              )
            else ...[
              HeroCarousel(slides: _slides(shell, shellRef)),
              const SizedBox(height: Sp.s8),
              _SectionHeader(
                title: 'Active projects',
                onViewAll: () => ref
                    .read(shellLocationProvider.notifier)
                    .go(const ProjectsLocation()),
              ),
              const SizedBox(height: Sp.s3),
              _CardRow(
                height: 352,
                children: [
                  SizedBox(
                    width: 208,
                    child: DashedCard(
                      icon: LucideIcons.plus,
                      label: 'New project',
                      caption: 'Or drop photos here',
                      onTap: () => createProjectFlow(context, ref),
                    ),
                  ),
                  for (final s in homeProjects(summaries, unsorted))
                    SizedBox(
                      width: 300,
                      child: ProjectCard(
                        key: ValueKey(s.project?.id ?? 'unsorted'),
                        summary: s,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Sp.s8),
            _SectionHeader(
              title: 'Looks & presets',
              onViewAll: () => ref
                  .read(shellLocationProvider.notifier)
                  .go(const LooksLocation()),
            ),
            const SizedBox(height: Sp.s3),
            LooksDropZone(
              builder: (context, dragging) => _CardRow(
                height: 252,
                children: [
                  SizedBox(
                    width: 176,
                    child: DashedCard(
                      icon: LucideIcons.fileUp,
                      label: 'Import presets & LUTs',
                      caption: 'Lightroom .xmp, .lrtemplate, .zip or .cube',
                      highlight: dragging,
                      onTap: () => pickAndImportLooks(context, ref),
                    ),
                  ),
                  for (final look in homeLooks(presets))
                    SizedBox(
                      width: 188,
                      child: LookCard(key: ValueKey(look.id), look: look),
                    ),
                ],
              ),
            ),
          ],
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, Sp.s6, Sp.s6, Sp.s10),
                  child: main,
                ),
              ),
              const SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(0, Sp.s6, Sp.s8, Sp.s10),
                  child: HomeSidebar(),
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, phone ? Sp.s4 : Sp.s6, pad, Sp.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              const SizedBox(height: Sp.s8),
              const HomeSidebar(showGreeting: false),
            ],
          ),
        );
      },
    );

    if (ref.watch(platformInfoProvider).supportsDragAndDrop) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) async {
          setState(() => _dragging = false);
          final files = await readXFiles(details.files);
          // A project card or the looks row under the pointer claims the
          // drop for itself.
          await DropClaim.unlessClaimed(() async {
            if (!shell.mounted) return;
            await importDroppedLooks(shell, shellRef, details.files);
            if (files.isNotEmpty && shell.mounted) {
              await importWithDestination(shell, shellRef, files);
            }
          });
        },
        child: Stack(
          children: [
            Positioned.fill(child: body),
            if (_dragging && !isNew)
              Positioned(
                left: 0,
                right: 0,
                bottom: Sp.s6,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Sp.s4,
                        vertical: Sp.s2,
                      ),
                      decoration: BoxDecoration(
                        color: t.textPrimary,
                        borderRadius: BorderRadius.circular(Rad.pill),
                        boxShadow: Elevation.e2,
                      ),
                      child: Text(
                        'Drop on a project to add to it, or anywhere to choose',
                        style: LumenType.label().copyWith(color: t.surface1),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return body;
  }
}

class _TopRow extends ConsumerWidget {
  const _TopRow({required this.showGreeting, required this.onImport});

  final bool showGreeting;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final name = ref.watch(settingsProvider).value?.displayName;
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    final mac = ref.watch(platformInfoProvider).isMacOS;
    return Padding(
      // The phone layout has no rail to keep clear of the window buttons.
      padding: EdgeInsets.only(top: phone && mac ? Sp.s5 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  homeDateLabel(DateTime.now()).toUpperCase(),
                  style: LumenType.micro().copyWith(color: t.textTertiary),
                ),
                if (showGreeting) ...[
                  const SizedBox(height: Sp.s1),
                  Text(
                    greetingFor(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (phone
                                ? LumenType.titleSerif(touch: true)
                                : LumenType.display())
                            .copyWith(color: t.textPrimary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Sp.s3),
          LumenButton(
            label: 'Import',
            icon: const Icon(LucideIcons.imagePlus),
            kind: ButtonKind.primary,
            height: 36,
            onPressed: onImport,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onViewAll});

  final String title;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: LumenType.titleSerif().copyWith(color: t.textPrimary),
          ),
        ),
        Pressable(
          onTap: onViewAll,
          semanticLabel: 'View all $title',
          scaleOnPress: false,
          radius: Rad.sm,
          builder: (context, states) {
            final c = states.contains(WidgetState.hovered)
                ? t.accent
                : t.textSecondary;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.s1,
                vertical: Sp.s1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View all', style: LumenType.label().copyWith(color: c)),
                  Icon(LucideIcons.chevronRight, size: 14, color: c),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A horizontal row of fixed-size cards; the shadows get room to show.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // The row fades out at the right edge: there is more to scroll to.
    return SizedBox(
      height: height + Sp.s4 + Sp.s1,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [1 - 48 / rect.width, 1],
        ).createShader(rect),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // Room for the hover lift above and the shadow below.
          padding: const EdgeInsets.only(top: Sp.s1, bottom: Sp.s4),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: Sp.s4),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.dragging, required this.onChoose});

  final bool dragging;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    return Container(
      padding: EdgeInsets.all(phone ? Sp.s5 : Sp.s10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(Rad.sheet),
        boxShadow: Elevation.e1,
      ),
      child: EmptyLibrary(
        dragging: dragging,
        onChoose: onChoose,
        embedded: true,
      ),
    );
  }
}
