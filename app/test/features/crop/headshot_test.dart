import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/crop/crop_panel.dart';
import 'package:lumen/features/crop/headshot.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen_core/lumen_core.dart';

import '../masks/masks_harness.dart';

/// One upright face in a 400×300 photo: irises at y = 120, chin at 170.
FaceCacheEntry _faces({bool withFace = true, bool rejectedOnly = false}) {
  final lm = List<double>.filled(MeshKeypoints.pointCount * 2, 0);
  void put(int i, double x, double y) {
    lm[2 * i] = x / 400;
    lm[2 * i + 1] = y / 300;
  }

  for (var i = 0; i < MeshKeypoints.pointCount; i++) {
    put(i, 200, 140);
  }
  put(MeshKeypoints.rightEyeOuter, 180, 120);
  put(MeshKeypoints.leftEyeOuter, 220, 120);
  put(MeshKeypoints.rightIrisCenter, 188, 120);
  put(MeshKeypoints.leftIrisCenter, 212, 120);
  put(MeshKeypoints.chin, 200, 170);
  const box = FaceBox(0.425, 0.35, 0.15, 0.25);
  return FaceCacheEntry(
    models: const {},
    analysis: FaceAnalysis(
      imageWidth: 400,
      imageHeight: 300,
      modelVersion: 'v',
      faces: [
        if (withFace && !rejectedOnly)
          DetectedFace(id: 'f', box: box, landmarks: lm),
      ],
    ),
    rejected: [
      if (rejectedOnly)
        const RejectedFace(
          id: 'r',
          box: box,
          reason: FaceRejectReason.tooSmall,
        ),
      const RejectedFace(
        id: 'noise',
        box: FaceBox(0, 0, 0.1, 0.1),
        reason: FaceRejectReason.lowPresence,
      ),
    ],
  );
}

Future<ProviderContainer> _editor(Future<FaceCacheEntry> Function() faces) =>
    openEditor(
      overrides: [faceAnalysisProvider(kAsset).overrideWith((ref) => faces())],
    );

Future<void> _tapHeadshot(WidgetTester tester, String ratio) async {
  final chip = find.text(ratio).last; // the Headshot row follows Aspect
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Widget _panel() => const CropPanel(assetId: kAsset, imageAspect: 400 / 300);

void main() {
  test('headshot faces: accepted plus size/yaw rejects, never noise', () {
    expect(headshotFaces(_faces()).map((f) => f.id), ['f']);
    expect(headshotFaces(_faces(rejectedOnly: true)).map((f) => f.id), ['r']);
    expect(
      headshotFor(_faces(withFace: false), Geometry.none, HeadshotRatio.square),
      isNull,
    );
  });

  testWidgets('Headshot 4:5 commits one undoable geometry entry', (
    tester,
  ) async {
    final c = await _editor(() async => _faces());
    await pumpIn(tester, c, _panel());
    await _tapHeadshot(tester, '4:5');

    final g = editor(c).settings.geometry;
    expect(g.aspect, '4:5');
    expect(g.crop.isFull, isFalse);
    expect(g.crop.width * 400 / (g.crop.height * 300), closeTo(0.8, 1e-6));
    expect(editor(c).history.entries.last.label, 'Headshot crop 4:5');
    // Eyes on the upper third of the crop.
    expect((120 / 300 - g.crop.top) / g.crop.height, closeTo(1 / 3, 1e-6));

    c.read(editorProvider(kAsset).notifier).undo();
    await tester.pumpAndSettle();
    expect(editor(c).settings.geometry, Geometry.none);
    await flushSave(tester);
  });

  testWidgets('no face: a toast, and the geometry is untouched', (
    tester,
  ) async {
    final c = await _editor(() async => _faces(withFace: false));
    await pumpIn(tester, c, _panel());
    await _tapHeadshot(tester, '1:1');
    expect(find.text('No face found for a headshot crop.'), findsOneWidget);
    expect(editor(c).settings.geometry, Geometry.none);
    await tester.pump(const Duration(seconds: 5));
    await flushSave(tester);
  });

  testWidgets('face detection unavailable: an honest toast', (tester) async {
    final c = await _editor(() async => throw const FormatException('no'));
    await pumpIn(tester, c, _panel());
    await _tapHeadshot(tester, '2:3');
    expect(find.textContaining('needs face detection'), findsOneWidget);
    expect(editor(c).settings.geometry, Geometry.none);
    await tester.pump(const Duration(seconds: 5));
    await flushSave(tester);
  });

  testWidgets('batch: crops photos with a face, skips the rest', (
    tester,
  ) async {
    final repo = MemoryCatalogRepository();
    for (final id in ['a', 'b']) {
      await repo.add(
        CatalogEntry(
          assetId: id,
          fileName: '$id.jpg',
          originalPath: 'originals/$id.jpg',
          format: 'jpeg',
          width: 400,
          height: 300,
          bytes: 1,
          importedAt: DateTime.utc(2026),
        ),
        Uint8List(1),
      );
    }
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          faceAnalysisProvider('a').overrideWith((ref) async => _faces()),
          faceAnalysisProvider('b')
              .overrideWith((ref) async => _faces(withFace: false)),
        ],
        child: MaterialApp(
          theme: buildLumenTheme(),
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final progress = <int>[];
    final result = (await tester.runAsync(
      () => headshotCropAssets(
        captured,
        ['a', 'b'],
        HeadshotRatio.square,
        onProgress: (done, _) => progress.add(done),
      ),
    ))!;
    expect(result, (cropped: 1, noFace: 1, failed: 0));
    expect(progress, [1, 2]);
    final a = await repo.loadEdit('a');
    expect(a.settings.geometry.aspect, '1:1');
    expect(a.history.entries.last.label, 'Headshot crop 1:1');
    expect((await repo.loadEdit('b')).settings.geometry, Geometry.none);
  });
}
