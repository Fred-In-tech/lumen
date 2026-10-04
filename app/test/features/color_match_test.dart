import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/ai/ai_auto_run.dart';
import 'package:lumen/features/ai/color_match_run.dart';
import 'package:lumen/features/ai/color_match_service.dart';
import 'package:lumen/features/batch/batch_color_match.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen_core/lumen_core.dart';

Uint8List _png(RgbaBuffer b) => Uint8List.fromList(
  img.encodePng(
    img.Image.fromBytes(
      width: b.width,
      height: b.height,
      bytes: b.data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
  ),
);

final _chart = SyntheticScenes.build(
  SceneId.wellExposedChart,
  longEdge: 400,
).image;

CatalogEntry _entry(String id) => CatalogEntry(
  assetId: id,
  fileName: '$id.png',
  originalPath: 'originals/$id.png',
  format: 'png',
  width: _chart.width,
  height: _chart.height,
  bytes: 1,
  importedAt: DateTime.utc(2026),
);

/// 'ref' is edited warm; the others are unedited copies of the same scene.
Future<MemoryCatalogRepository> _catalog(List<String> ids) async {
  final repo = MemoryCatalogRepository();
  for (final id in ['ref', ...ids]) {
    await repo.add(_entry(id), _png(_chart));
  }
  await repo.saveEdit(
    EditDocument.create('ref')
        .copyWith(settings: DevelopSettings.defaults.withValue(P.temp, 35)),
  );
  return repo;
}

Future<WidgetRef> _harness(
  WidgetTester tester,
  MemoryCatalogRepository repo,
) async {
  late WidgetRef ref;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: Consumer(
        builder: (context, r, _) {
          ref = r;
          return const SizedBox();
        },
      ),
    ),
  );
  return ref;
}

void main() {
  testWidgets('Match look: one AI history entry, AI Amount scales it, '
      'portrait and hand-set sliders are kept', (tester) async {
    late MemoryCatalogRepository repo;
    await tester.runAsync(() async => repo = await _catalog(['a']));
    final ref = await _harness(tester, repo);
    await tester.runAsync(() async {
      await ref.read(editorProvider('a').future);
      final ctl = ref.read(editorProvider('a').notifier);
      final s0 = ref.read(editorProvider('a')).value!.settings;
      // A portrait value, and a hand-set vibrance (locked for AI).
      ctl.commit(
        s0
            .copyWith(
              portrait: PortraitSettings.empty.withGroupValue(
                FaceGroup.all,
                PortraitIds.skinSoftening,
                30,
              ),
            )
            .withValue(P.vibrance, 10),
        label: 'Manual',
      );
      final before = ref.read(editorProvider('a')).value!;
      final n = await runColorMatch(ref, 'a', _entry('ref'));
      expect(n, greaterThan(0));
      final s = ref.read(editorProvider('a')).value!;
      expect(s.history.entries, hasLength(2));
      final entry = s.history.entries.last;
      expect(entry.kind, HistoryKind.ai);
      expect(entry.label, 'Color match · ref.png');
      expect(s.settings.value(P.temp), greaterThan(12));
      expect(s.settings.value(P.vibrance), 10, reason: 'hand-set: locked');
      expect(s.settings.portrait, before.settings.portrait);
      expect(s.doc.ai?.style, 'color_match');
      final half = applyAiAmountWithRetouch(
        pre: s.doc.ai!.preAi,
        ai: s.doc.ai!.postAi!,
        percent: 50,
      );
      expect(half.value(P.temp), closeTo(s.settings.value(P.temp) / 2, 1));
      ctl.undo();
      expect(ref.read(editorProvider('a')).value!.settings, before.settings);
      await ctl.flush();
    });
  });

  testWidgets('batch Match look: each photo matched once, the reference '
      'untouched', (tester) async {
    late MemoryCatalogRepository repo;
    await tester.runAsync(() async => repo = await _catalog(['a', 'b']));
    final ref = await _harness(tester, repo);
    await tester.runAsync(() async {
      final (ok, failed) = await batchColorMatch(ref, [
        'ref',
        'a',
        'b',
      ], _entry('ref'));
      expect((ok, failed), (2, 0));
      for (final id in ['a', 'b']) {
        final doc = await repo.loadEdit(id);
        expect(doc.history.entries.single.label, 'Color match · ref.png');
        expect(doc.history.entries.single.kind, HistoryKind.ai);
        expect(doc.settings.value(P.temp), greaterThan(12));
        expect(await repo.readThumb(id), isNotNull);
        expect((await repo.get(id))!.hasEdits, isTrue);
      }
      final refDoc = await repo.loadEdit('ref');
      expect(refDoc.history.entries, isEmpty);
    });
  });

  test('the last edited photo is the default reference', () {
    final a = _entry('a')
        .copyWith(hasEdits: true, editedAt: DateTime.utc(2026, 1, 2));
    final b = _entry('b')
        .copyWith(hasEdits: true, editedAt: DateTime.utc(2026, 1, 3));
    final c = _entry('c');
    expect(lastEditedExcept([a, b, c], null)?.assetId, 'b');
    expect(lastEditedExcept([a, b, c], 'b')?.assetId, 'a');
    expect(lastEditedExcept([c], null), isNull);
  });
}
