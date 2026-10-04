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

/// The shoulders (below 64 %) of the scene's person raster: its clothes.
final _clothes = MaskRaster(
  _scene.people.width,
  _scene.people.height,
  Uint8List.fromList([
    for (var i = 0; i < _scene.people.data.length; i++)
      (i ~/ _scene.people.width) >= 0.64 * _scene.people.height
          ? _scene.people.data[i]
          : 0,
  ]),
);

DevelopSettings _clothing(double wrinkles) => DevelopSettings.defaults.copyWith(
  portrait: PortraitSettings.empty.withImageValue(
    PortraitIds.clothesWrinkles,
    wrinkles,
  ),
);

class _FakeSource implements AiMaskSource {
  _FakeSource({this.fail = false, this.clothes = true});
  final bool fail;
  final bool clothes;
  final segmented = <MaskKind>[];

  @override
  bool supports(MaskKind kind) => kind != MaskKind.clothes || clothes;

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
      switch (maskRef) {
        'person' => _scene.people,
        'clothes' => _clothes,
        _ => _scene.hair,
      };
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

    test('clothing edits load only the clothes raster', () async {
      final source = _FakeSource();
      final input = await loadBackdropRasters(
        source,
        _FakeLoader(),
        'p',
        want: (backdrop: false, clothes: true),
      );
      expect(source.segmented, [MaskKind.clothes]);
      expect(input.clothes, same(_clothes));
      expect(input.people, isNull);
      expect(input.wantsBackdrop, isFalse);
      expect(input.wantsClothes, isTrue);
    });

    test('backdrop and clothing edits load all three', () async {
      final source = _FakeSource();
      final input = await loadBackdropRasters(
        source,
        _FakeLoader(),
        'p',
        want: (backdrop: true, clothes: true),
      );
      expect(source.segmented, [
        MaskKind.person,
        MaskKind.hair,
        MaskKind.clothes,
      ]);
      expect(input.people, same(_scene.people));
      expect(input.clothes, same(_clothes));
    });

    test('no clothes model: the clothes raster stays null and the maps say '
        'why', () async {
      final input = await loadBackdropRasters(
        _FakeSource(clothes: false),
        _FakeLoader(),
        'p',
        want: (backdrop: false, clothes: true),
      );
      expect(input.clothes, isNull);
      expect(input.wantsClothes, isTrue);
      final maps = computeBackdropMaps(_scene.image, input);
      expect(maps.clothesState, ClothesState.noMatte);
      expect(maps.clothesState.reason, isNotNull);
      expect(
        await loadBackdropRasters(
          _FakeSource(fail: true),
          _FakeLoader(),
          'p',
          want: (backdrop: true, clothes: true),
        ),
        isA<BackdropInput>()
            .having((i) => i.people, 'people', isNull)
            .having((i) => i.clothes, 'clothes', isNull)
            .having((i) => i.wantsClothes, 'wantsClothes', isTrue),
      );
    });

    test('imageRasterRequest asks only for what the values need', () {
      expect(imageRasterRequest(PortraitSettings.empty), isNull);
      expect(imageRasterRequest(_backdrop(50).portrait), (
        backdrop: true,
        clothes: false,
      ));
      expect(imageRasterRequest(_clothing(50).portrait), (
        backdrop: false,
        clothes: true,
      ));
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
        backdrop: (id, want) async {
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

    test('clothing-only edits build clothes maps (and ask only for the '
        'clothes raster)', () async {
      final asked = <ImageRasterRequest>[];
      final loader = StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _noFaces(cache),
        backdrop: (id, want) async {
          asked.add(want);
          return BackdropInput(
            clothes: _clothes,
            wantsBackdrop: want.backdrop,
            wantsClothes: want.clothes,
          );
        },
      );
      final r = await loader.load('p', _clothing(100));
      expect(asked, [(backdrop: false, clothes: true)]);
      expect(r.maps?.backdrop.clothesState, ClothesState.ready);
      expect(r.maps?.backdrop.state, BackdropState.notRequested);
      final u = RetouchUniforms.fromSettings(_clothing(100).portrait, r.faces!);
      expect(RetouchPassUniforms.isActive(r.maps!, u), isTrue);
      final out = applyRetouch(_scene.image, r.maps!, u);
      expect(identical(out, _scene.image), isFalse);
    });

    test('no backdrop edits: no rasters are loaded', () async {
      var loads = 0;
      final loader = StoredRetouchLoader(
        catalog: repo,
        faceService: () async => _noFaces(cache),
        backdrop: (id, want) async {
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
    expect(c.read(clothesStatusProvider('p')), isNull);
  });

  test('clothesStatusProvider reports why the clothing sliders do '
      'nothing', () async {
    final repo = await _catalog();
    await repo.saveEdit(
      EditDocument.create('p').copyWith(settings: _clothing(60)),
    );
    final maps = computeRetouchMaps(
      _scene.image,
      _scene.analysis,
      backdrop: const BackdropInput(wantsBackdrop: false, wantsClothes: true),
    );
    final c = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        retouchMapsBuildProvider('p')
            .overrideWith((ref) async => (maps: maps, faces: _scene.analysis)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider('p').future);
    c.read(retouchInputsProvider('p'));
    await c.read(retouchMapsBuildProvider('p').future);
    expect(c.read(clothesStatusProvider('p')), ClothesState.noMatte);
    expect(c.read(backdropStatusProvider('p')), BackdropState.notRequested);
  });
}
