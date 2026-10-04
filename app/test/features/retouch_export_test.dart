import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

const _n = 320;
final _portrait = renderSynthPortrait(_n, _n, const [
  SynthFace(id: 'f', cx: 160, cy: 130, iod: 90),
]);

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
      _png(_portrait.image),
    );
  }
  return repo;
}

final _retouched = DevelopSettings.defaults.copyWith(
  portrait: PortraitPresets.autoRetouch(PortraitSettings.empty),
);

/// The face box in pixels, grown by [margin] of its size.
PixelBox _faceBox({double margin = 0}) {
  final b = _portrait.analysis.faces.single.box;
  final mx = b.width * margin, my = b.height * margin;
  return PixelBox.fromLTRB(
    ((b.x - mx) * _n).floor(),
    ((b.y - my) * _n).floor(),
    ((b.x + b.width + mx) * _n).ceil(),
    ((b.y + b.height + my) * _n).ceil(),
  );
}

/// Pixels that differ, inside and outside [box].
({int inside, int outside}) _diff(img.Image a, img.Image b, PixelBox box) {
  var inside = 0, outside = 0;
  for (var y = 0; y < _n; y++) {
    for (var x = 0; x < _n; x++) {
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      if (p.r == q.r && p.g == q.g && p.b == q.b) continue;
      final inBox = x >= box.x && x < box.right && y >= box.y && y < box.bottom;
      inBox ? inside++ : outside++;
    }
  }
  return (inside: inside, outside: outside);
}

Future<img.Image> _export(ExportService s, String id) async => img.decodePng(
  (await s.exportOne(id, const ExportOptions(format: ExportFormat.png))).bytes,
)!;

FaceAnalysisService _service({
  FaceCache? cache,
  Future<FaceAnalyzer> Function()? analyzer,
}) => FaceAnalysisService(
  cache: cache ?? MemoryFaceCache(),
  models: kFaceModels,
  analyzer:
      analyzer ??
      () => Future.error(const InferenceUnavailable('no runtime here')),
);

/// Analysis that "detects" the synthetic portrait's face (the real models
/// are covered by the on-device tests): exercises the cache-miss path.
class _SynthAnalysis extends FaceAnalysisService {
  _SynthAnalysis(FaceCache cache)
    : super(
        cache: cache,
        models: kFaceModels,
        analyzer: () => Future.error(const InferenceUnavailable('unused')),
      );

  int runs = 0;
  (int, int)? decoded;

  @override
  Future<FaceCacheEntry> analyze(
    String assetId, {
    required PixelLoader pixels,
    int? sourceWidth,
    int? sourceHeight,
    bool force = false,
  }) async {
    runs++;
    final px = await pixels();
    decoded = (px.width, px.height);
    final entry = FaceCacheEntry(
      models: kFaceModels,
      analysis: _portrait.analysis,
    );
    await cache.write(assetId, entry);
    return entry;
  }
}

void main() {
  test('an export with portrait edits differs from one without, inside '
      'the face only', () async {
    final repo = await _catalog(['p']);
    final cache = MemoryFaceCache();
    await cache.write(
      'p',
      FaceCacheEntry(models: kFaceModels, analysis: _portrait.analysis),
    );
    final service = ExportService(
      repo,
      retouch: StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _service(cache: cache),
      ).load,
    );
    final plain = await _export(service, 'p');
    await repo.saveEdit(
      EditDocument.create('p').copyWith(settings: _retouched),
    );
    final retouched = await _export(service, 'p');
    final d = _diff(plain, retouched, _faceBox(margin: 0.25));
    expect(d.inside, greaterThan(500));
    expect(d.outside, 0, reason: 'retouch stays on the face');
  });

  test('a batch export of never-opened photos analyzes faces, caches them '
      'and applies Auto Retouch', () async {
    final repo = await _catalog(['p', 'q']);
    await repo.saveEdit(
      EditDocument.create('p').copyWith(settings: _retouched),
    );
    final faces = _SynthAnalysis(MemoryFaceCache());
    final service = ExportService(
      repo,
      retouch: StoredRetouchLoader(
        catalog: repo,
        faceService: () async => faces,
      ).load,
    );
    final exports = {
      for (final id in ['p', 'q']) id: await _export(service, id),
    };
    expect(faces.runs, 1, reason: 'only the retouched photo needs faces');
    expect(faces.decoded, (_n, _n), reason: 'it analyzed the original');
    expect(await faces.cached('p'), isNotNull, reason: 'analysis cached');
    final d = _diff(exports['q']!, exports['p']!, PixelBox.zero);
    expect(d.outside, greaterThan(200), reason: 'retouch applied');
  });

  test('batch thumbnails apply portrait retouch', () async {
    final repo = await _catalog(['p']);
    final cache = MemoryFaceCache();
    await cache.write(
      'p',
      FaceCacheEntry(models: kFaceModels, analysis: _portrait.analysis),
    );
    final loader = StoredRetouchLoader(
      catalog: repo,
      faceService: () async => _service(cache: cache),
    );
    Future<img.Image> thumb(DevelopSettings s) async {
      await refreshThumbnail(repo, 'p', s, retouch: loader.load);
      return img.decodePng((await repo.readThumb('p'))!)!;
    }

    final plain = await thumb(DevelopSettings.defaults);
    final retouched = await thumb(_retouched);
    var changed = 0;
    for (var y = 0; y < plain.height; y++) {
      for (var x = 0; x < plain.width; x++) {
        if (plain.getPixel(x, y) != retouched.getPixel(x, y)) changed++;
      }
    }
    expect(changed, greaterThan(200));
  });

  test('when face analysis fails the export still completes, with a '
      'note', () async {
    final repo = await _catalog(['p']);
    final service = ExportService(
      repo,
      retouch: StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _service(),
      ).load,
    );
    final plain = await _export(service, 'p');
    await repo.saveEdit(
      EditDocument.create('p').copyWith(settings: _retouched),
    );
    final out = await service.exportOne(
      'p',
      const ExportOptions(format: ExportFormat.png),
    );
    expect(out.note, kRetouchSkippedNote);
    final d = _diff(plain, img.decodePng(out.bytes)!, PixelBox.zero);
    expect(d.outside, 0, reason: 'exported without retouch');
  });

  test('GPU export keeps heal, retouch and the long edge', () async {
    final repo = await _catalog(['p']);
    final cache = MemoryFaceCache();
    await cache.write(
      'p',
      FaceCacheEntry(models: kFaceModels, analysis: _portrait.analysis),
    );
    final store = MemoryPatchStore();
    const box = PixelBox(4, 4, 40, 30); // a corner, away from the face
    final heal = HealOp.forPatch(
      id: 'h1',
      bbox: box,
      srcWidth: _n,
      srcHeight: _n,
      engine: 'patchmatch@1',
      ai: false,
      strokes: const [],
    );
    await store.save('p', heal.patch, RgbaBuffer.filled(40, 30, 20, 200, 40));
    final service = ExportService(
      repo,
      patches: () async => store,
      retouch: StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _service(cache: cache),
      ).load,
      sourceRenderer: const GpuSourceRenderer(),
    );
    Future<img.Image> export(DevelopSettings s) async {
      await repo.saveEdit(EditDocument.create('p').copyWith(settings: s));
      final f = await service.exportOne(
        'p',
        const ExportOptions(format: ExportFormat.png, longEdge: 160),
      );
      expect(f.note, isNull);
      return img.decodePng(f.bytes)!;
    }

    final healed = await export(
      DevelopSettings.defaults.copyWith(heal: [heal]),
    );
    expect((healed.width, healed.height), (160, 160));
    final c = healed.getPixel(12, 8);
    expect((c.r < 60, c.g > 170), (true, true), reason: 'patch drawn');
    final both = await export(_retouched.copyWith(heal: [heal]));
    var inFace = 0, outside = 0;
    final face = _faceBox(margin: 0.25);
    for (var y = 0; y < 160; y++) {
      for (var x = 0; x < 160; x++) {
        final p = healed.getPixel(x, y), q = both.getPixel(x, y);
        final d = [
          (p.r - q.r).abs(),
          (p.g - q.g).abs(),
          (p.b - q.b).abs(),
        ].reduce((a, b) => a > b ? a : b);
        if (d <= 1) continue;
        final inBox =
            x * 2 >= face.x &&
            x * 2 < face.right &&
            y * 2 >= face.y &&
            y * 2 < face.bottom;
        inBox ? inFace++ : outside++;
      }
    }
    expect(inFace, greaterThan(100), reason: 'pass R ran on the GPU');
    expect(outside, 0);
  });

  group('heals on faces feed the retouch analysis', () {
    HealOp op(String id, PixelBox box, {bool hidden = false}) =>
        HealOp.forPatch(
          id: id,
          bbox: box,
          srcWidth: _n,
          srcHeight: _n,
          engine: 'patchmatch@1',
          ai: false,
          strokes: const [],
        ).copyWith(hidden: hidden);

    final face = op('f', const PixelBox(150, 140, 30, 20));
    final corner = op('c', const PixelBox(0, 0, 12, 6));

    test('only visible heals touching a face count', () {
      final a = _portrait.analysis;
      expect(healOpsOnFaces([face, corner], a), [face]);
      expect(healOpsOnFaces([face.copyWith(hidden: true)], a), isEmpty);
      expect(faceHealKey([corner], a), '');
      expect(faceHealKey([corner, face], a), 'f');
    });

    test('the maps rebuild from healed pixels only when a face heal '
        'changes', () async {
      final repo = await _catalog(['p']);
      final store = MemoryPatchStore();
      for (final o in [face, corner]) {
        await store.save(
          'p',
          o.patch,
          RgbaBuffer.filled(o.bbox.width, o.bbox.height, 20, 200, 40),
        );
      }
      final c = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          patchStoreProvider.overrideWith((ref) async => store),
          faceAnalysisProvider('p').overrideWith(
            (ref) async => FaceCacheEntry(
              models: kFaceModels,
              analysis: _portrait.analysis,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(editorProvider('p').future);
      final sub = c.listen(retouchMapsBuildProvider('p'), (_, _) {});
      addTearDown(sub.close);
      final first = (await c.read(retouchMapsBuildProvider('p').future))!;

      final ctl = c.read(editorProvider('p').notifier);
      DevelopSettings s() => c.read(editorProvider('p')).value!.settings;
      ctl.commit(s().copyWith(heal: [corner]), label: 'Remove');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final second = await c.read(retouchMapsBuildProvider('p').future);
      expect(
        identical(second, first),
        isTrue,
        reason: 'corner heal: no rebuild',
      );

      ctl.commit(s().copyWith(heal: [corner, face]), label: 'Remove');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final third = (await c.read(retouchMapsBuildProvider('p').future))!;
      expect(identical(third, first), isFalse);
      expect(
        listEquals(third.maps.b1, first.maps.b1),
        isFalse,
        reason: 'built from the healed face',
      );

      final pixels = await healedAnalysisPixels(
        _portrait.image,
        assetId: 'p',
        ops: [corner, face],
        faces: _portrait.analysis,
        patches: () async => store,
      );
      final p = pixels.offset(160, 150), q = pixels.offset(5, 3);
      expect(pixels.data.sublist(p, p + 3), [20, 200, 40]);
      expect(
        pixels.data.sublist(q, q + 3),
        _portrait.image.data.sublist(q, q + 3),
        reason: 'heals away from faces are left out',
      );
      await ctl.flush();
    });
  });
}
