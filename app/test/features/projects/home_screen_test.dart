import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/app_settings.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/features/home/home_screen.dart';
import 'package:lumen/features/home/home_sidebar.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/projects/projects_page.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/project_fixtures.dart';

void main() {
  testWidgets('a new user sees one welcoming import card, no rows', (
    tester,
  ) async {
    await pumpApp(tester, MemoryCatalogRepository());
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('developed.'), findsOneWidget);
    expect(find.text('Choose photos'), findsOneWidget);
    expect(find.text('Active projects'), findsNothing);
    expect(find.text('Looks & presets'), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Import your first shoot to begin.'), findsOneWidget);
  });

  testWidgets('projects, looks, greeting by name and this week', (
    tester,
  ) async {
    final (repo, _, _) = await twoProjectLibrary();
    final settings = MemorySettingsRepository();
    await settings.save(const AppSettings(displayName: 'Sam'));
    final c = await pumpApp(tester, repo, settings: settings);

    expect(find.text('Welcome back, Sam'), findsOneWidget);
    expect(find.text('Active projects'), findsOneWidget);
    expect(find.text('Looks & presets'), findsOneWidget);
    expect(find.text('New project'), findsOneWidget);
    expect(find.text('Wedding'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Unsorted'), findsOneWidget);
    // Next steps from the progress rules.
    expect(find.text('Edit 1 pick'), findsOneWidget); // Wedding: all flagged
    expect(find.text('Cull 2 photos'), findsOneWidget); // Family
    expect(find.text('Cull 1 photo'), findsOneWidget); // Unsorted
    // The hero, with a button that does the thing.
    expect(find.text('Edit RAW with 32-bit precision.'), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Auto Retouch that keeps skin texture.'), findsOneWidget);
    // Looks: dashed card first, then AI styles as cards.
    expect(find.text('Create a preset'), findsOneWidget);
    expect(find.text('Moody'), findsOneWidget);

    await tester.tap(find.text('View all').first);
    await tester.pumpAndSettle();
    expect(c.read(shellLocationProvider), const ProjectsLocation());
    expect(find.byType(ProjectsPage), findsOneWidget);
  });

  testWidgets('a project card opens its project', (tester) async {
    final (repo, wedding, _) = await twoProjectLibrary();
    final c = await pumpApp(tester, repo);
    await tester.tap(find.text('Wedding'));
    await tester.pumpAndSettle();
    expect(c.read(shellLocationProvider), ProjectLocation(wedding));
    expect(find.text('Export picks'), findsOneWidget);
  });

  test('home rows: unfinished projects first, then finished, then '
      'Unsorted', () {
    ProjectSummary s(String name, List<CatalogEntry> photos) => summarize(
      Project(
        id: name,
        name: name,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      photos,
      (accepted: const {}, faces: const {}),
    );
    final done = s('done', [
      photo(
        'a',
        flag: PhotoFlag.pick,
        edited: true,
      ).copyWith(exportedAt: DateTime.utc(2026, 10, 3)),
    ]);
    final open = s('open', [photo('b')]);
    final unsorted = summarize(
      null,
      [photo('u')],
      (accepted: const {}, faces: const {}),
    );
    expect(homeProjects([done, open], unsorted).map((x) => x.name), [
      'open',
      'done',
      'Unsorted',
    ]);
    expect(homeProjects([done, open], null, max: 1).map((x) => x.name), [
      'open',
    ]);
  });

  test('greeting and date label', () {
    expect(greetingFor(null), 'Welcome back');
    expect(greetingFor('Sam'), 'Welcome back, Sam');
    expect(homeDateLabel(DateTime(2026, 10, 7)), 'Wednesday 7 October');
  });

  test('display names are trimmed and capped; blank clears', () {
    expect(AppSettings.cleanDisplayName('  Sam '), 'Sam');
    expect(AppSettings.cleanDisplayName('   '), isNull);
    expect(AppSettings.cleanDisplayName(42), isNull);
    expect(AppSettings.cleanDisplayName('x' * 60), hasLength(40));
    final s = const AppSettings().copyWith(displayName: 'Ama');
    expect(AppSettings.fromJson(s.toJson()).displayName, 'Ama');
    expect(s.copyWith(clearDisplayName: true).displayName, isNull);
  });
}
