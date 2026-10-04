import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/features/ai/ai_auto_run.dart';
import 'package:lumen/features/ai/auto_retouch.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/batch/remeasure_sync.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

const _n = 320;

/// 'acne': the default synthetic face (spots, pores). 'clean': no spots,
/// fine pores. 'none': a scene without faces. Others fail analysis.
final Map<String, SynthPortrait> _photos = {
  'acne': renderSynthPortrait(_n, _n, const [
    SynthFace(id: 'f', cx: 160, cy: 130, iod: 90),
  ]),
  'clean': renderSynthPortrait(_n, _n, const [
    SynthFace(id: 'f', cx: 160, cy: 130, iod: 90, spots: [], poreAmp: 0.003),
  ]),
};

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

Future<MemoryCatalogRepository> _catalog(List<String> ids) async {
  final repo = MemoryCatalogRepository();
  for (final id in ids) {
    await repo.add(
      CatalogEntry(
        assetId: id,
        fileName: '$id.png',
        originalPath: 'originals/$id.png',
        format: 'png',
        width: _n,
        height: _n,
        bytes: 1,
        importedAt: DateTime.utc(2026),
      ),
      _png(
        _photos[id]?.image ??
            SyntheticScenes.build(SceneId.values.first, longEdge: _n).image,
      ),
    );
  }
  return repo;
}

/// "Detects" the synthetic faces (the real models are covered by the
/// on-device tests); photos it does not know fail like a missing runtime.
class _SynthFaces extends FaceAnalysisService {
  _SynthFaces()
    : super(
        cache: MemoryFaceCache(),
        models: kFaceModels,
        analyzer: () => Future.error(const InferenceUnavailable('unused')),
      );

  final runs = <String>[];

  @override
  Future<FaceCacheEntry> analyze(
    String assetId, {
    required PixelLoader pixels,
    int? sourceWidth,
    int? sourceHeight,
    bool force = false,
  }) async {
    runs.add(assetId);
    if (assetId == 'broken') throw const InferenceUnavailable('no models');
    final analysis =
        _photos[assetId]?.analysis ??
        const FaceAnalysis(imageWidth: _n, imageHeight: _n, modelVersion: 's');
    final entry = FaceCacheEntry(models: kFaceModels, analysis: analysis);
    await cache.write(assetId, entry);
    return entry;
  }
}

StoredAutoRetouchPlanner _planner(MemoryCatalogRepository repo) =>
    StoredAutoRetouchPlanner(
      catalog: repo,
      faceService: () async => _SynthFaces(),
    );

double _acne(PortraitSettings p) =>
    p.groupValue(FaceGroup.all, PortraitIds.acne);

void main() {
  test('Auto = colour + need-scaled retouch in ONE AI history entry; hand-set '
      'values stay', () async {
    final repo = await _catalog(['acne']);
    final c = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider('acne').future);
    final ctl = c.read(editorProvider('acne').notifier);
    // The user sets Iris by hand first (a slider entry): it is locked.
    final s0 = c.read(editorProvider('acne')).value!.settings;
    ctl.commit(
      s0.copyWith(
        portrait: s0.portrait.withGroupValue(
          FaceGroup.all,
          PortraitIds.iris,
          70,
        ),
      ),
      label: 'Iris 70',
    );
    final state = c.read(editorProvider('acne')).value!;
    final planner = _planner(repo);
    final service = AutoEditService(local: const LocalAutoEditProvider());
    final result = await service.autoEdit(
      AiPhotoContext(
        proxy: AuxMaps.proxy(_photos['acne']!.image, longEdge: 256),
        current: state.settings,
        retouch: () => planner.plan('acne', state.doc),
      ),
    );
    ctl.applyAi(result.outcome.settings, result.record, label: result.label);

    final after = c.read(editorProvider('acne')).value!;
    expect(after.history.entries, hasLength(2));
    final ai = after.history.entries.last;
    expect(ai.kind, HistoryKind.ai);
    expect(ai.label, endsWith('+ Retouch'));
    expect(ai.ops.map((o) => o.path), contains('portrait'));
    expect(ai.ops.any((o) => o.path.startsWith('values.')), isTrue);
    final p = after.settings.portrait;
    expect(p.groupValue(FaceGroup.all, PortraitIds.iris), 70, reason: 'locked');
    expect(_acne(p), greaterThan(60), reason: 'acne face: strong acne value');
    expect(
      p.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
      lessThanOrEqualTo(55),
    );
    // One undo removes colour and retouch together.
    ctl.undo();
    expect(
      c.read(editorProvider('acne')).value!.settings.portrait,
      state.settings.portrait,
    );
    // AI amount scales the retouch with the colour (never past 100 %).
    final half = applyAiAmountWithRetouch(
      pre: state.settings,
      ai: result.outcome.settings,
      percent: 50,
    );
    expect(_acne(half.portrait), closeTo(_acne(p) / 2, 1));
    final more = applyAiAmountWithRetouch(
      pre: state.settings,
      ai: result.outcome.settings,
      percent: 150,
    );
    expect(_acne(more.portrait), _acne(p));
    await ctl.flush();
  });

  test('clean skin gets lighter values than problem skin', () async {
    final repo = await _catalog(['acne', 'clean']);
    final planner = _planner(repo);
    final acne = await planner.plan('acne', EditDocument.create('acne'));
    final clean = await planner.plan('clean', EditDocument.create('clean'));
    expect(_acne(acne.portrait!), greaterThan(_acne(clean.portrait!) + 20));
    expect(
      clean.portrait!.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
      lessThan(
        acne.portrait!.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
      ),
    );
    final none = await _planner(await _catalog(['none']))
        .plan('none', EditDocument.create('none'));
    expect(none.portrait, isNull, reason: 'no faces: portrait untouched');
    expect(none.note, isNull);
  });

  testWidgets('batch auto-edit of unopened photos retouches faces; a failed '
      'analysis is a note, not a failure', (tester) async {
    late MemoryCatalogRepository repo;
    await tester.runAsync(() async {
      repo = await _catalog(['acne', 'broken']);
    });
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
          autoEditServiceProvider.overrideWithValue(
            AutoEditService(local: const LocalAutoEditProvider()),
          ),
          autoRetouchPlannerProvider.overrideWithValue(_planner(repo)),
        ],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.runAsync(() async {
      final notes = <String, String>{};
      final (ok, failed) = await batchAutoEdit(ref, [
        'acne',
        'broken',
      ], onNote: (id, note) => notes[id] = note);
      expect((ok, failed), (2, 0));
      expect(notes.keys, ['broken']);
      expect(notes['broken'], kFacesNotRetouchedNote);
      final a = await repo.loadEdit('acne');
      expect(a.history.entries.single.kind, HistoryKind.ai);
      expect(a.settings.portrait.hasFaceEdits, isTrue);
      expect(_acne(a.settings.portrait), greaterThan(60));
      final b = await repo.loadEdit('broken');
      expect(b.settings.portrait.hasFaceEdits, isFalse);
      expect(b.ai, isNotNull, reason: 'the colour edit still landed');
    });
  });

  testWidgets('Auto Retouch + Sync re-measures each photo', (tester) async {
    late MemoryCatalogRepository repo;
    late PortraitSettings sourcePortrait;
    await tester.runAsync(() async {
      repo = await _catalog(['acne', 'clean']);
      final plan = await _planner(repo)
          .plan('acne', EditDocument.create('acne'));
      // The user also nudged skin softening up by 5 on the source.
      sourcePortrait = plan.portrait!.withGroupValue(
        FaceGroup.all,
        PortraitIds.skinSoftening,
        plan.portrait!.groupValue(FaceGroup.all, PortraitIds.skinSoftening) + 5,
      );
    });
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
    await tester.runAsync(() async {
      final source = DevelopSettings.defaults.copyWith(
        portrait: sourcePortrait,
      );
      await syncSettingsToAssets(
        ref,
        source,
        {SettingsGroup.portrait},
        ['clean'],
        sourceAssetId: 'acne',
      );
      final pasted = (await repo.loadEdit('clean')).settings.portrait;
      expect(_acne(pasted), _acne(sourcePortrait), reason: 'plain paste');
      final r = await remeasureSyncedRetouch(
        repo: repo,
        planner: _planner(repo),
        sourceAssetId: 'acne',
        sourceSettings: source,
        targets: ['acne', 'clean'],
      );
      expect(r.remeasured, 1);
      final doc = await repo.loadEdit('clean');
      expect(doc.history.entries, hasLength(1), reason: 'still one entry');
      expect(doc.history.entries.single.label, 'Paste settings');
      final own = await _planner(repo)
          .plan('clean', EditDocument.create('clean'));
      final p = doc.settings.portrait;
      expect(_acne(p), _acne(own.portrait!), reason: "clean photo's need");
      expect(
        p.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
        own.portrait!.groupValue(FaceGroup.all, PortraitIds.skinSoftening) + 5,
        reason: 'the source tweak survives as an offset',
      );
      // Undo of the paste restores the photo exactly.
      expect(
        doc.history.undo(doc.settings).settings.portrait,
        PortraitSettings.empty,
      );
    });
  });
}
