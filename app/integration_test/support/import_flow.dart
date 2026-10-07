import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/projects/import_destination.dart';

/// Pumps (letting real async work run) until [done] or [timeout].
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Answers the "Where should these go?" dialog: a new project (optionally
/// renamed to [projectName]), or with [existing] the first existing one.
Future<void> confirmImportDestination(
  WidgetTester tester, {
  String? projectName,
  bool existing = false,
}) async {
  await pumpUntilFound(tester, find.byType(ImportDestinationDialog));
  await tester.pumpAndSettle();
  if (existing) {
    await tester.tap(find.text('Add to a project'));
    await tester.pumpAndSettle();
  } else if (projectName != null) {
    await tester.enterText(
      find.byKey(const ValueKey('new-project-name')),
      projectName,
    );
    await tester.pump();
  }
  await tester.tap(find.textContaining(RegExp(r'^Import \d+ photos?$')));
  await tester.pump();
}

/// Taps the Import button and sends the photos to a new project.
Future<void> importToNewProject(WidgetTester tester, {String? name}) async {
  await tester.tap(find.text('Import').first);
  await confirmImportDestination(tester, projectName: name);
}
