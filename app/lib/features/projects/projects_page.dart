import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/projects/project_actions.dart';
import 'package:lumen/features/projects/project_card.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/page_header.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/dashed_card.dart';
import 'package:lumen/widgets/segmented.dart';

/// How the Projects grid is ordered.
enum ProjectSort {
  recent('Recent'),
  name('Name'),
  date('Date');

  const ProjectSort(this.label);
  final String label;
}

/// [summaries] matching [query] (case-insensitive name search), in [sort]
/// order. Recent: latest activity first; Name: A–Z; Shoot date: newest.
List<ProjectSummary> sortAndFilterProjects(
  List<ProjectSummary> summaries,
  String query,
  ProjectSort sort,
) {
  final q = query.trim().toLowerCase();
  final out = [
    for (final s in summaries)
      if (q.isEmpty || s.name.toLowerCase().contains(q)) s,
  ];
  switch (sort) {
    case ProjectSort.recent:
      out.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    case ProjectSort.name:
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case ProjectSort.date:
      out.sort(
        (a, b) => b.project!.displayDate.compareTo(a.project!.displayDate),
      );
  }
  return out;
}

/// Grid of every project with search, sort and the context menu.
class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  final _search = TextEditingController();
  ProjectSort _sort = ProjectSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final all = ref.watch(projectSummariesProvider);
    final unsorted = ref.watch(unsortedSummaryProvider);
    final shown = sortAndFilterProjects(all, _search.text, _sort);
    final nav = ref.read(shellLocationProvider.notifier);
    final phone = MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint;
    final searching = _search.text.trim().isNotEmpty;
    final cards = <Widget>[
      if (!searching)
        DashedCard(
          key: const ValueKey('new-project'),
          icon: LucideIcons.plus,
          label: 'New project',
          caption: 'One shoot, from import to delivery',
          onTap: () => createProjectFlow(context, ref),
        ),
      for (final s in shown)
        ProjectCard(key: ValueKey(s.project!.id), summary: s),
      if (unsorted != null && !searching)
        ProjectCard(key: const ValueKey('unsorted'), summary: unsorted),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Projects',
          breadcrumb: [
            (label: 'Home', onTap: () => nav.go(const HomeLocation())),
            (label: 'Projects', onTap: null),
          ],
          subtitle: all.isEmpty
              ? 'Every shoot gets a project'
              : '${all.length} ${all.length == 1 ? 'project' : 'projects'}',
          actions: [
            if (phone)
              LumenButton(
                label: 'All photos',
                icon: const Icon(LucideIcons.images),
                onPressed: () => nav.go(const AllPhotosLocation()),
              ),
            LumenButton(
              label: 'New project',
              icon: const Icon(LucideIcons.plus),
              kind: ButtonKind.primary,
              onPressed: () => createProjectFlow(context, ref),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            phone ? Sp.s4 : Sp.s8,
            0,
            phone ? Sp.s4 : Sp.s8,
            Sp.s4,
          ),
          child: Wrap(
            spacing: Sp.s3,
            runSpacing: Sp.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: phone ? double.infinity : 280,
                height: 34,
                child: TextField(
                  key: const ValueKey('project-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: LumenType.body().copyWith(color: t.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search projects',
                    hintStyle: LumenType.body().copyWith(color: t.textTertiary),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 16,
                      color: t.textTertiary,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                    filled: true,
                    fillColor: t.surface1,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Rad.pill),
                      borderSide: BorderSide(color: t.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Rad.pill),
                      borderSide: BorderSide(color: t.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Rad.pill),
                      borderSide: BorderSide(color: t.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!phone) ...[
                    Text(
                      'Sort',
                      style: LumenType.label().copyWith(color: t.textTertiary),
                    ),
                    const SizedBox(width: Sp.s2),
                  ],
                  Segmented<ProjectSort>(
                    value: _sort,
                    height: 30,
                    options: {for (final s in ProjectSort.values) s: s.label},
                    onChanged: (s) => setState(() => _sort = s),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: searching && shown.isEmpty
              ? Center(
                  child: Text(
                    'No project matches “${_search.text.trim()}”.',
                    style: LumenType.body().copyWith(color: t.textSecondary),
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    phone ? Sp.s4 : Sp.s8,
                    Sp.s1,
                    phone ? Sp.s4 : Sp.s8,
                    Sp.s10,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: phone ? 420 : 320,
                    mainAxisExtent: 352,
                    mainAxisSpacing: Sp.s5,
                    crossAxisSpacing: Sp.s5,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (_, i) => cards[i],
                ),
        ),
      ],
    );
  }
}
