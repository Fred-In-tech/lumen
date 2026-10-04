import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_backdrop.dart';

final _scene = renderBackdropScene(w: 240, h: 180);

Future<MemoryCatalogRepository> _catalog() async {
  final repo = MemoryCatalogRepository();
  final b = _scene.image;
  await repo.add(
    CatalogEntry(
      assetId: 'p',
      fileName: 'p.png',
      originalPath: 'originals/p.png',
      format: 'png',
      width: b.width,
      height: b.height,
      bytes: 1,
      importedAt: DateTime.utc(2026),
    ),
    Uint8List.fromList(
      img.encodePng(
        img.Image.fromBytes(
          width: b.width,
          height: b.height,
          bytes: b.data.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        ),
      ),
    ),
  );
  return repo;
}

DevelopSettings _backdrop(double clean) => DevelopSettings.defaults.copyWith(
  portrait: PortraitSettings.empty.withImageValue(PortraitIds.bgClean, clean),
);

FaceAnalysisService _noFaces(FaceCache cache) => FaceAnalysisService(
  cache: cache,
  models: kFaceModels,
  analyzer: () => Future.error(const InferenceUnavailable('unused')),
);

class _FakeSource implements AiMaskSource {
  _FakeSource({this.fail = false});
  final bool fail;
  final segmented = <MaskKind>[];

  @override
  bool supports(MaskKind kind) => true;

  @override
  Future<AiShape> segment(String assetId, MaskKind kind) async {
    if (fail) throw Exception('model missing');
    segmented.add(kind);
    return AiShape(maskRef: kind.name, model: 'fake', modelVersion: '1');
  }
}

class _FakeLoader implements AiMaskRasterLoader {
  @override
  Future<MaskRaster?> load(String assetId, String maskRef) async =>
      maskRef == MaskKind.person.name ? _scene.people : _scene.hair;
}

void main() {
  group('loadBackdropRasters', () {
    test('loads the person and hair rasters through the AI masks', () async {
      final source = _FakeSource();
      final input = await loadBackdropRasters(source, _FakeLoader(), 'p');
      expect(input.people, same(_scene.people));
      expect(input.hair, same(_scene.hair));
      expect(source.segmented, [MaskKind.person, MaskKind.hair]);
    });

    test('is "missing" without masks (web, no model, failures)', () async {
      expect(
        await loadBackdropRasters(null, _FakeLoader(), 'p'),
        same(BackdropInput.missing),
      );
      expect(
        await loadBackdropRasters(_FakeSource(fail: true), _FakeLoader(), 'p'),
        same(BackdropInput.missing),
      );
    });
  });

  group('StoredRetouchLoader (export, batch, thumbnails)', () {
    late MemoryCatalogRepository repo;
    late MemoryFaceCache cache;
    setUp(() async {
      repo = await _catalog();
      cache = MemoryFaceCache();
      await cache.write(
        'p',
        FaceCacheEntry(models: kFaceModels, analysis: _scene.analysis),
      );
    });

    test('backdrop-only edits build backdrop maps for a photo without '
        'faces', () async {
      var loads = 0;
      final loader = StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _noFaces(cache),
        backdrop: (id) async {
          loads++;
          return _scene.input;
        },
      );
      final r = await loader.load('p', _backdrop(100));
      expect(loads, 1);
      expect(r.maps?.backdrop.state, BackdropState.ready);
      expect(r.faces, isNotNull);
      final u = RetouchUniforms.fromSettings(_backdrop(100).portrait, r.faces!);
      expect(RetouchPassUniforms.isActive(r.maps!, u), isTrue);
      final out = applyRetouch(_scene.image, r.maps!, u);
      expect(identical(out, _scene.image), isFalse);
    });

    test('no backdrop edits: no rasters are loaded', () async {
      var loads = 0;
      final loader = StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _noFaces(cache),
        backdrop: (id) async {
          loads++;
          return _scene.input;
        },
      );
      final r = await loader.load('p', DevelopSettings.defaults);
      expect(r.maps, isNull);
      expect(loads, 0);
    });

    test('without masks the backdrop edit is skipped', () async {
      final loader = StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _noFaces(cache),
      );
      final r = await loader.load('p', _backdrop(100));
      expect(r.maps, isNull);
      expect(r.note, isNull);
    });
  });

  test('the editor builds retouch inputs as soon as a backdrop value is '
      'set', () async {
    final repo = await _catalog();
    await repo.saveEdit(
      EditDocument.create('p').copyWith(settings: _backdrop(60)),
    );
    var builds = 0;
    final c = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        retouchMapsBuildProvider('p').overrideWith((ref) async {
          builds++;
          return null;
        }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider('p').future);
    c.read(retouchInputsProvider('p'));
    await Future<void>.delayed(Duration.zero);
    expect(builds, 1);
    expect(c.read(backdropStatusProvider('p')), isNull);
  });
}
