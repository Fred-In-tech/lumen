// End-to-end portrait flow on the real app, GPU and on-device models:
// import a sample portrait → open it (Auto mode) → faces detected → Auto
// Retouch → the rendered frame is a real retouched photo (not white) →
// Manual → Portrait tools → back to Auto → click into the prompt bar, click
// the canvas, hold "\" → before/after.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/photo_canvas.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen_core/lumen_core.dart';

import 'support/import_flow.dart';

import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_sources.dart';

import 'support/sample_photos.dart';

class _FakeImportSource implements ImportSource {
  _FakeImportSource(this.files);
  final List<ImportFile> files;

  @override
  Future<List<ImportFile>> pick({required bool mobile}) async => files;
}

final _shotKey = GlobalKey();

Future<void> _screenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('${Directory.systemTemp.path}/lumen_shots')
      ..createSync(recursive: true);
    final f = File('${dir.path}/$name.png')
      ..writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('SCREENSHOT ${f.path}');
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

/// The editor's current rendered frame as RGBA.
Future<Uint8List> _frame(WidgetTester tester) async {
  final canvas = tester.widget<PhotoCanvas>(find.byType(PhotoCanvas));
  final image = canvas.after.value!;
  late Uint8List out;
  await tester.runAsync(() async {
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    out = bd!.buffer.asUint8List();
  });
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portrait: detect → Auto Retouch renders a real photo → \\ '
      'compares even after typing in the prompt bar', (tester) async {
    final root = Directory.systemTemp.createTempSync('lumen_portrait');
    final catalog = FileCatalogRepository(root.path);
    final sample = samplePortraitJpeg();
    File('${Directory.systemTemp.path}/lumen_sample_portrait.jpg')
        .writeAsBytesSync(sample);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(catalog),
          presetRepositoryProvider.overrideWithValue(
            FilePresetRepository(root.path),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FileSettingsRepository(root.path),
          ),
          importSourceProvider.overrideWithValue(
            _FakeImportSource([
              ImportFile(name: 'sample_portrait.jpg', bytes: sample),
            ]),
          ),
        ],
        child: RepaintBoundary(key: _shotKey, child: const LumenApp()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LumenApp)),
    );

    await importToNewProject(tester, name: 'Portrait session');
    await _pumpUntil(
      tester,
      () => (container.read(libraryProvider).value?.length ?? 0) == 1,
    );
    final id = container.read(libraryProvider).value!.single.assetId;
    await _settle(tester, 3000);
    await _screenshot(tester, 'p0_library');

    final tile = find.bySemanticsLabel(RegExp('sample_portrait.jpg')).first;
    await tester.tap(tile);
    await _pumpUntil(
      tester,
      () => container.read(editorProvider(id)).value != null,
    );
    await _pumpUntil(
      tester,
      () =>
          tester.widgetList<PhotoCanvas>(find.byType(PhotoCanvas)).isNotEmpty &&
          tester.widget<PhotoCanvas>(find.byType(PhotoCanvas)).after.value !=
              null,
    );
    await _settle(tester);
    // Auto-edit on import may have set colour; start retouch from there.
    await _screenshot(tester, 'p1_editor');

    // Auto mode: faces are detected on device for the Retouch step.
    expect(container.read(editorModeProvider), EditorMode.auto);
    await _pumpUntil(
      tester,
      () =>
          container.read(portraitFacesStatusProvider(id)).value?.faces.length ==
          1,
    );
    await _settle(tester);
    await _screenshot(tester, 'p2_faces');

    await tester.tap(find.text('Auto Retouch'));
    await _pumpUntil(
      tester,
      () => container
          .read(editorProvider(id))
          .value!
          .settings
          .portrait
          .hasFaceEdits,
    );
    // Retouch maps build in the background, then the frame re-renders.
    await _settle(tester, 6000);
    final retouched = await _frame(tester);
    await _screenshot(tester, 'p3_auto_retouch');

    // Not white, not blank: a real photo.
    var sum = 0, white = 0;
    for (var i = 0; i < retouched.length; i += 4) {
      final l = retouched[i] + retouched[i + 1] + retouched[i + 2];
      sum += l;
      if (l >= 3 * 250) white++;
    }
    final pixels = retouched.length ~/ 4;
    expect(white / pixels, lessThan(0.2), reason: 'frame is mostly white');
    expect(sum / pixels / 3, inInclusiveRange(40, 220));
    // Retouch visibly changes the photo: strong retouch vs none.
    final ctl = container.read(editorProvider(id).notifier);
    final base = container.read(editorProvider(id)).value!.settings;
    var strong = PortraitSettings.empty;
    for (final e in {
      PortraitIds.skinSoftening: 100.0,
      PortraitIds.skinEven: 80.0,
      PortraitIds.acne: 100.0,
      PortraitIds.freckle: 100.0,
      PortraitIds.eyeWhites: 60.0,
      PortraitIds.teethBrightness: 60.0,
    }.entries) {
      strong = strong.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    ctl.commit(base.copyWith(portrait: strong), label: 'Strong retouch');
    await _settle(tester, 4000);
    final on = await _frame(tester);
    await _screenshot(tester, 'p3b_strong_retouch');
    ctl.commit(
      base.copyWith(portrait: PortraitSettings.empty),
      label: 'No retouch',
    );
    await _settle(tester, 3000);
    final off = await _frame(tester);
    var changed = 0;
    for (var i = 0; i < math.min(on.length, off.length); i += 4) {
      if ((on[i] - off[i]).abs() + (on[i + 1] - off[i + 1]).abs() > 6) {
        changed++;
      }
    }
    debugPrint('RESULT retouch changed $changed of ${on.length ~/ 4} px');
    expect(changed, greaterThan(500), reason: 'retouch had no visible effect');
    expect(changed, lessThan(on.length ~/ 4 ~/ 3), reason: 'not face-local');
    ctl.commit(base, label: 'Back to Auto Retouch');
    await _settle(tester, 2000);

    // Manual: the Portrait tools, one part of the face at a time.
    await tester.tap(find.bySemanticsLabel('Manual mode'));
    await _settle(tester, 800);
    await _screenshot(tester, 'p5_manual_adjust');
    await tester.tap(find.byTooltip('Portrait').first);
    await tester.pump();
    expect(container.read(editorModuleProvider(id)), EditorModule.portrait);
    await _settle(tester, 1500);
    await _screenshot(tester, 'p6_manual_portrait');
    await tester.tap(find.bySemanticsLabel('Scene tools'));
    await _settle(tester, 800);
    await _screenshot(tester, 'p7_manual_portrait_scene');
    await tester.tap(find.byTooltip('Crop').first);
    await _settle(tester, 800);
    await _screenshot(tester, 'p8_manual_crop');
    await tester.tap(find.bySemanticsLabel('Auto mode'));
    await _settle(tester, 800);
    expect(container.read(editorModuleProvider(id)), EditorModule.adjust);

    // Click into the prompt bar, then the photo: "\" must reach the editor.
    final field = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('Describe an edit'),
    );
    if (field.evaluate().isNotEmpty) {
      await tester.tap(field.first);
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(PhotoCanvas)));
      await tester.pump();
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backslash);
    await tester.pump();
    expect(container.read(editorProvider(id)).value!.showingBefore, isTrue);
    await _settle(tester, 1500);
    await _screenshot(tester, 'p4_before_held');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backslash);
    await tester.pump();
    expect(container.read(editorProvider(id)).value!.showingBefore, isFalse);
    if (field.evaluate().isNotEmpty) {
      expect(
        tester.widget<TextField>(field.first).controller?.text ?? '',
        isNot(contains(r'\')),
      );
    }
    await _settle(tester, 500);
  });
}
