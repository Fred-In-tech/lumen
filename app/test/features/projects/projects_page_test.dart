import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/projects/projects_page.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/project_fixtures.dart';

Future<void> _openProjects(WidgetTester tester) async {
  await tester.tap(find.text('Projects').first);
  await tester.pumpAndSettle();
  expect(find.byType(ProjectsPage), findsOneWidget);
}

/// Opens the "…" menu of the project card named [name].
Future<void> _menu(WidgetTester tester, String name) async {
  final card = find.ancestor(
    of: find.text(name),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'ProjectCard',
    ),
  );
  await tester.tap(
    find.descendant(of: card, matching: find.byTooltip('Project actions')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search narrows the grid; sort orders it', (tester) async {
    final (repo, _, _) = await twoProjectLibrary();
    await pumpApp(tester, repo);
    await _openProjects(tester);
    expect(find.text('2 projects'), findsOneWidget);
    expect(find.text('Wedding'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('project-search')), 'wed');
    await tester.pumpAndSettle();
    expect(find.text('Wedding'), findsOneWidget);
    expect(find.text('Family'), findsNothing);
    expect(find.text('Unsorted'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('project-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No project matches “zzz”.'), findsOneWidget);
  });

  test('sortAndFilterProjects: recent, name, shoot date', () {
    ProjectSummary s(String name, DateTime shoot, DateTime updated) =>
        summarize(
          Project(
            id: name,
            name: name,
            createdAt: updated,
            updatedAt: updated,
            shootDate: shoot,
          ),
          const [],
          (accepted: const {}, faces: const {}),
        );
    final a = s('beta', DateTime(2026, 1, 5), DateTime.utc(2026, 3));
    final b = s('Alpha', DateTime(2026, 2, 5), DateTime.utc(2026, 1));
    final c = s('gamma', DateTime(2025, 12, 5), DateTime.utc(2026, 2));
    List<String> names(ProjectSort sort, [String q = '']) => [
      for (final x in sortAndFilterProjects([a, b, c], q, sort)) x.name,
    ];
    expect(names(ProjectSort.recent), ['beta', 'gamma', 'Alpha']);
    expect(names(ProjectSort.name), ['Alpha', 'beta', 'gamma']);
    expect(names(ProjectSort.date), ['Alpha', 'beta', 'gamma']);
    expect(names(ProjectSort.name, 'A'), ['Alpha', 'beta', 'gamma']);
    expect(names(ProjectSort.name, 'mm'), ['gamma']);
  });

  testWidgets('context menu: rename', (tester) async {
    final (repo, wedding, _) = await twoProjectLibrary();
    await pumpApp(tester, repo);
    await _openProjects(tester);
    await _menu(tester, 'Wedding');
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('project-name-field')),
      'Ama & Kofi wedding',
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Ama & Kofi wedding'), findsOneWidget);
    final projects = await repo.listProjects();
    expect(
      projects.firstWhere((p) => p.id == wedding).name,
      'Ama & Kofi wedding',
    );
  });

  testWidgets('context menu: set cover', (tester) async {
    final (repo, wedding, _) = await twoProjectLibrary();
    await pumpApp(tester, repo);
    await _openProjects(tester);
    await _menu(tester, 'Wedding');
    await tester.tap(find.text('Set cover…'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a cover'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Use w2.jpg as cover'));
    await tester.pumpAndSettle();
    final p = (await repo.listProjects()).firstWhere((p) => p.id == wedding);
    expect(p.coverAssetId, 'w2');
  });

  testWidgets('delete keeps the photos as Unsorted by default', (tester) async {
    final (repo, wedding, _) = await twoProjectLibrary();
    await pumpApp(tester, repo);
    await _openProjects(tester);
    await _menu(tester, 'Wedding');
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteProjectDialog), findsOneWidget);
    expect(find.text('Delete “Wedding”?'), findsOneWidget);
    expect(find.text('Keep the 3 photos'), findsOneWidget);
    expect(find.text('Delete the 3 photos too'), findsOneWidget);
    await tester.tap(find.text('Delete project'));
    await tester.pumpAndSettle();
    expect(
      (await repo.listProjects()).map((p) => p.id),
      isNot(contains(wedding)),
    );
    expect((await repo.get('w1'))!.projectId, isNull);
    expect(find.text('Wedding'), findsNothing);
  });

  testWidgets('delete with photos names the count and removes them', (
    tester,
  ) async {
    final (repo, _, _) = await twoProjectLibrary();
    await pumpApp(tester, repo);
    await _openProjects(tester);
    await _menu(tester, 'Wedding');
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete the 3 photos too'));
    await tester.pumpAndSettle();
    expect(find.text('Delete project and 3 photos'), findsOneWidget);
    await tester.tap(find.text('Delete project and 3 photos'));
    await tester.pumpAndSettle();
    for (final id in ['w1', 'w2', 'w3']) {
      expect(await repo.get(id), isNull);
    }
    expect(await repo.get('f1'), isNotNull);
  });

  testWidgets('cancel leaves everything as it was', (tester) async {
    final (repo, _, _) = await twoProjectLibrary();
    await pumpApp(tester, repo);
    await _openProjects(tester);
    await _menu(tester, 'Family');
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await repo.listProjects(), hasLength(2));
  });

  testWidgets('New project asks for a name and opens it', (tester) async {
    final (repo, _, _) = await twoProjectLibrary();
    final c = await pumpApp(tester, repo);
    await _openProjects(tester);
    await tester.tap(find.text('New project').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('project-name-field')),
      'Studio day',
    );
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();
    final created = (await repo.listProjects()).firstWhere(
      (p) => p.name == 'Studio day',
    );
    expect(c.read(shellLocationProvider), ProjectLocation(created.id));
    expect(find.text('Add the photos of this shoot'), findsOneWidget);
  });
}
