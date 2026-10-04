import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/remove/ai_remover.dart';
import 'package:lumen/features/remove/remove_canvas.dart';
import 'package:lumen/features/remove/remove_panel.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/features/remove/remove_status.dart';
import 'package:lumen/features/remove/remove_status_card.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen_core/lumen_core.dart';

import 'remove_fixtures.dart';

class _NoAi implements AiRemoverLoader {
  @override
  int get downloadBytes => 16312640;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<InpaintModel> load({
    required void Function(double? fraction) onProgress,
    CancelToken? cancel,
  }) => Future.error(const InferenceUnavailable('none'));
}

const _view = Size(400, 300); // 4:3 like the 160×120 source

Future<ProviderContainer> _pump(WidgetTester tester, InlineRunner run) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = MemoryCatalogRepository();
  final store = MemoryPatchStore();
  await tester.runAsync(
    () => repo.add(
      CatalogEntry(
        assetId: 'a',
        fileName: 'a.jpg',
        originalPath: 'originals/a.jpg',
        format: 'jpeg',
        width: kW,
        height: kH,
        bytes: 1,
        importedAt: DateTime.utc(2026),
      ),
      Uint8List(1),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        patchStoreProvider.overrideWith((ref) async => store),
        removeSourceLoaderProvider.overrideWithValue(
          (_) async => syntheticPhoto(),
        ),
        cancellableRunnerProvider.overrideWithValue(run.call),
        aiRemoverLoaderProvider.overrideWithValue(_NoAi()),
        portraitFacesStatusProvider.overrideWith(
          (ref, id) => const AsyncData(null),
        ),
      ],
      child: MaterialApp(
        theme: buildLumenTheme(),
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 320,
                child: SingleChildScrollView(child: RemovePanel(assetId: 'a')),
              ),
              SizedBox.fromSize(
                size: _view,
                child: RemoveCanvas(
                  assetId: 'a',
                  mapping: CanvasMapping(
                    geometry: Geometry.none,
                    source: const Size(kW + 0.0, kH + 0.0),
                    view: _view,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  final c = ProviderScope.containerOf(tester.element(find.byType(RemovePanel)));
  await tester.runAsync(() => c.read(editorProvider('a').future));
  await tester.pumpAndSettle();
  return c;
}

/// Alternates real time (isolates, timers) with pumps (the gesture's
/// futures live in the test zone) until [ok] holds.
Future<void> _until(WidgetTester tester, bool Function() ok) async {
  for (var i = 0; i < 400 && !ok(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue, reason: 'condition never held');
  // Not pumpAndSettle: the running spinner animates forever.
  await tester.pump();
}

Offset _canvasAt(WidgetTester tester, double fx, double fy) {
  final tl = tester.getTopLeft(find.byType(RemoveCanvas));
  return tl + Offset(_view.width * fx, _view.height * fy);
}

void main() {
  testWidgets('a painted stroke becomes a listed fix; hide and delete are '
      'history entries', (tester) async {
    final c = await _pump(tester, InlineRunner());
    expect(find.text(RemovePanel.emptyHint), findsOneWidget);
    c.read(removeUiProvider('a').notifier).setSize(30);

    await tester.dragFrom(_canvasAt(tester, 0.5, 0.5), const Offset(30, 0));
    await _until(tester, () => c.read(removeStatusProvider('a')) is RemoveDone);

    final s = c.read(editorProvider('a')).value!;
    expect(s.history.entries.single.label, 'Remove');
    final op = s.settings.heal.single;
    expect(op.strokes.single.points.length, greaterThan(1));
    expect(find.textContaining('Remove 1', findRichText: true), findsOneWidget);
    expect(find.text(RemovePanel.emptyHint), findsNothing);

    await tester.tap(find.byTooltip('Hide Remove 1'));
    await tester.pumpAndSettle();
    var now = c.read(editorProvider('a')).value!;
    expect(now.settings.heal.single.hidden, isTrue);
    expect(now.history.entries.last.label, 'Hide Remove 1');

    await tester.tap(find.byTooltip('Delete Remove 1'));
    await tester.pumpAndSettle();
    now = c.read(editorProvider('a')).value!;
    expect(now.settings.heal, isEmpty);
    expect(now.history.entries.map((e) => e.label), [
      'Remove',
      'Hide Remove 1',
      'Delete Remove 1',
    ]);
    expect(find.text('Deleted Remove 1.'), findsOneWidget);
    await tester.runAsync(() => c.read(editorProvider('a').notifier).flush());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('while running: the method chip, the stroke and Cancel', (
    tester,
  ) async {
    final run = InlineRunner()..hang.add(1); // plan runs, the fill hangs
    final c = await _pump(tester, run);
    c.read(removeUiProvider('a').notifier).setSize(40);
    await tester.dragFrom(_canvasAt(tester, 0.5, 0.5), const Offset(40, 0));
    await _until(
      tester,
      () => switch (c.read(removeStatusProvider('a'))) {
        RemoveRunning(method: InpaintMethod.patchMatch) => true,
        _ => false,
      },
    );
    expect(find.text('Patch fill'), findsOneWidget);
    expect(c.read(removeUiProvider('a')).pending, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await _until(tester, () => c.read(removeStatusProvider('a')) is RemoveIdle);
    expect(run.tasks[1].isCancelled, isTrue);
    expect(c.read(editorProvider('a')).value!.history.entries, isEmpty);
    expect(c.read(removeUiProvider('a')).pending, isEmpty);
  });

  testWidgets('clone needs a source: Alt-click or "Set source" then paint', (
    tester,
  ) async {
    final c = await _pump(tester, InlineRunner());
    await tester.tap(find.text('Clone'));
    await tester.pumpAndSettle();
    await tester.tapAt(_canvasAt(tester, 0.7, 0.5));
    await tester.pumpAndSettle();
    expect(
      find.text('Alt-click (Option-click) to choose what to copy, then paint.'),
      findsOneWidget,
    );
    expect(c.read(removeStatusProvider('a')), isA<RemoveIdle>());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tapAt(_canvasAt(tester, 0.25, 0.5));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    var src = c.read(removeUiProvider('a')).source!;
    expect(src.$1, closeTo(0.25, 0.01));

    await tester.tap(find.text('Set source'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the photo to choose the source'), findsOneWidget);
    await tester.tapAt(_canvasAt(tester, 0.3, 0.5));
    await tester.pumpAndSettle();
    src = c.read(removeUiProvider('a')).source!;
    expect(src.$1, closeTo(0.3, 0.01));

    await tester.dragFrom(_canvasAt(tester, 0.75, 0.5), const Offset(0, 20));
    await _until(tester, () => c.read(removeStatusProvider('a')) is RemoveDone);
    final op = c.read(editorProvider('a')).value!.settings.heal.single;
    expect(op.kind, HealKind.clone);
    expect(op.cloneOffset!.$1, closeTo(-0.45, 0.01));
    expect(find.textContaining('Clone 1', findRichText: true), findsOneWidget);
    await tester.runAsync(() => c.read(editorProvider('a').notifier).flush());
  });

  testWidgets('AI badge on model fills and the face warning', (tester) async {
    final c = await _pump(tester, InlineRunner());
    final ai = HealOp.forPatch(
      id: 'h1',
      bbox: const PixelBox(1, 1, 4, 4),
      srcWidth: kW,
      srcHeight: kH,
      engine: 'migan@fp16-1',
      ai: true,
      strokes: const [],
      faceIntersect: true,
    );
    final ctl = c.read(editorProvider('a').notifier);
    ctl.commit(
      c.read(editorProvider('a')).value!.settings.copyWith(heal: [ai]),
      label: 'Remove',
    );
    c
        .read(removeStatusNotifier)
        .report(RemoveDone(kind: HealKind.remove, ops: [ai]));
    await tester.pumpAndSettle();
    expect(find.text('AI'), findsOneWidget);
    expect(find.textContaining('AI fill', findRichText: true), findsWidgets);
    expect(find.text(RemoveStatusCard.faceWarning), findsOneWidget);
    expect(
      find.byTooltip('Removing over a face can look unnatural'),
      findsOneWidget,
    );
    await tester.runAsync(() => ctl.flush());
  });
}

final removeStatusNotifier = removeStatusProvider('a').notifier;
