import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/projects/import_destination.dart';
import 'package:lumen/features/projects/project_page.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/project_fixtures.dart';

Uint8List _jpeg(int seed) {
  final im = img.Image(width: 24, height: 16);
  img.fill(im, color: img.ColorRgb8(30 * seed, 200 - 20 * seed, 90));
  return Uint8List.fromList(img.encodeJpg(im));
}

bool _tile(String id) => find.byKey(ValueKey(id)).evaluate().isNotEmpty;

void main() {
  testWidgets('a project page: breadcrumb, progress and only its photos', (
    tester,
  ) async {
    final (repo, wedding, _) = await twoProjectLibrary();
    final c = await pumpApp(tester, repo);
    c.read(shellLocationProvider.notifier).go(ProjectLocation(wedding));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectPage), findsOneWidget);
    expect(find.text('Wedding'), findsWidgets);
    expect(find.text('Projects'), findsWidgets); // rail + breadcrumb
    expect(find.text('27 Sep 2026  ·  3 photos'), findsOneWidget);
    // Detailed progress: counts per step and the next step.
    expect(find.text('3 of 3 culled'), findsOneWidget);
    expect(find.text('1 of 2 picks edited'), findsOneWidget);
    expect(find.text('Edit 1 pick'), findsOneWidget);
    expect(find.text('Export picks'), findsOneWidget);
    // The grid holds the project's photos only.
    expect(['w1', 'w2', 'w3'].every(_tile), isTrue);
    expect(['f1', 'f2', 'u1'].any(_tile), isFalse);

    // Breadcrumb back to Projects, then Home.
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(c.read(shellLocationProvider), const ProjectsLocation());
    expect(c.read(shellLocationProvider.notifier).back(), isTrue);
    await tester.pumpAndSettle();
    expect(c.read(shellLocationProvider), const HomeLocation());
    expect(c.read(shellLocationProvider.notifier).back(), isFalse);
  });

  testWidgets('Unsorted has no progress or project menu', (tester) async {
    final (repo, _, _) = await twoProjectLibrary();
    final c = await pumpApp(tester, repo);
    c.read(shellLocationProvider.notifier).go(const ProjectLocation(null));
    await tester.pumpAndSettle();
    expect(find.textContaining('Photos that are not in a project'), findsOne);
    expect(find.text('Next step'), findsNothing);
    expect(find.byTooltip('Project actions'), findsNothing);
    expect(_tile('u1'), isTrue);
    expect(_tile('w1'), isFalse);
  });

  testWidgets('selected photos move to another project', (tester) async {
    final (repo, wedding, family) = await twoProjectLibrary();
    final c = await pumpApp(tester, repo);
    c.read(shellLocationProvider.notifier).go(ProjectLocation(wedding));
    await tester.pumpAndSettle();
    c.read(selectionProvider.notifier).selectAll(['w2', 'w3']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family').last);
    await tester.pumpAndSettle();
    expect((await repo.get('w2'))!.projectId, family);
    expect((await repo.get('w3'))!.projectId, family);
    expect((await repo.get('w1'))!.projectId, wedding);
    expect(c.read(selectionProvider).isEmpty, isTrue);
    expect(_tile('w2'), isFalse, reason: 'left this project');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Add photos imports straight into the project', (tester) async {
    final (repo, _, family) = await twoProjectLibrary();
    final c = await pumpApp(
      tester,
      repo,
      pick: [ImportFile(name: 'new.jpg', bytes: _jpeg(1))],
    );
    c.read(shellLocationProvider.notifier).go(ProjectLocation(family));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Add photos'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ImportDestinationDialog), findsNothing);
    final added = (await repo.list()).firstWhere(
      (e) => e.fileName == 'new.jpg',
    );
    expect(added.projectId, family);
  });

  testWidgets('Import asks where; a new project is created and opened', (
    tester,
  ) async {
    final repo = MemoryCatalogRepository();
    final c = await pumpApp(
      tester,
      repo,
      pick: [
        ImportFile(name: 'IMG_0420.jpg', bytes: _jpeg(1)),
        ImportFile(name: 'IMG_0421.jpg', bytes: _jpeg(2)),
      ],
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Import'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ImportDestinationDialog), findsOneWidget);
    expect(find.text('Where should these go?'), findsOneWidget);
    // Prefilled from the day and the first file (no EXIF date here).
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('new-project-name')),
    );
    expect(field.controller!.text, endsWith('· IMG_0420'));
    // No projects yet: no "Add to a project" option.
    expect(find.text('Add to a project'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('new-project-name')),
      'Studio test',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Import 2 photos'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();
    final project = (await repo.listProjects()).single;
    expect(project.name, 'Studio test');
    expect(c.read(shellLocationProvider), ProjectLocation(project.id));
    final all = await repo.list();
    expect(all, hasLength(2));
    expect(all.every((e) => e.projectId == project.id), isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the dialog offers existing projects and Unsorted', (
    tester,
  ) async {
    final (repo, wedding, _) = await twoProjectLibrary();
    final projects = await repo.listProjects();
    ImportDestination? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showImportDestinationDialog(
              context,
              count: 1,
              suggestedName: '7 Oct 2026 · IMG_1',
              projects: projects,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text('Import 1 photo'), findsOneWidget);
    await tester.tap(find.text('Add to a project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 1 photo'));
    await tester.pumpAndSettle();
    expect(result, isA<ExistingProjectDestination>());
    // The most recently changed project comes first (here: Family, made last).
    expect(
      (result! as ExistingProjectDestination).projectId,
      projects.first.id,
    );

    await open();
    await tester.tap(find.text('Unsorted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 1 photo'));
    await tester.pumpAndSettle();
    expect(result, isA<UnsortedDestination>());

    await open();
    await tester.enterText(find.byKey(const ValueKey('new-project-name')), '');
    await tester.pump();
    await tester.tap(find.text('Import 1 photo'));
    await tester.pumpAndSettle();
    expect(
      find.byType(ImportDestinationDialog),
      findsOneWidget,
      reason: 'a blank name cannot be imported into',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(wedding, isNotEmpty);
  });

  test('editor back label names the project of the photos', () {
    final p = Project(
      id: 'p',
      name: 'Wedding',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final lib = [
      photo('a', project: 'p'),
      photo('b', project: 'p'),
      photo('c'),
    ];
    expect(backLabelFor(['a', 'b'], lib, [p]), 'Wedding');
    expect(backLabelFor(['c'], lib, [p]), 'Unsorted');
    expect(backLabelFor(['a', 'c'], lib, [p]), 'All photos');
    expect(backLabelFor(['a'], lib, const []), 'All photos');
  });

  test('cull facts: accepted suggestions and face counts', () {
    CullRecord rec(int faces, SuggestionStatus status) => CullRecord(
      signalsKey: 'k',
      signals: CullSignals(
        sharpness: 0.3,
        highlightClip: 0,
        shadowClip: 0,
        meanLuma: 0.5,
        dHash: '0000000000000000',
        faces: [
          for (var i = 0; i < faces; i++)
            FaceCullSignal(faceId: 'f$i', area: 0.1, sharpness: 0.5),
        ],
      ),
      status: status,
    );
    final facts = cullFactsOf({
      'a': rec(2, SuggestionStatus.accepted),
      'b': rec(0, SuggestionStatus.pending),
      'c': rec(1, SuggestionStatus.dismissed),
    });
    expect(facts.accepted, {'a'});
    expect(facts.faces, {'a': 2, 'c': 1});
  });
}
