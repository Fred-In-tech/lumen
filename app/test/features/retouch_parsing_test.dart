import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_parser.dart';
import 'package:lumen/ai/ondevice/face_parsing_cache.dart';
import 'package:lumen/ai/ondevice/face_parsing_cache_io.dart';
import 'package:lumen/ai/ondevice/fake_inference_backend.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen/features/portrait/retouch_parsing.dart';
import 'package:lumen/features/portrait/retouch_tiles.dart';
import 'package:lumen/platform/platform_info.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import '../../../packages/lumen_core/test/retouch/support/synthetic_parsing.dart';
import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

const _id = 'p';
const _spec = ModelManifest.selfieMulticlass;

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

Future<MemoryCatalogRepository> _catalog(
  RgbaBuffer image, {
  Uint8List? raw,
}) async {
  final repo = MemoryCatalogRepository();
  await repo.add(
    CatalogEntry(
      assetId: _id,
      fileName: '$_id.png',
      originalPath: 'originals/$_id.png',
      format: 'png',
      width: image.width,
      height: image.height,
      bytes: 1,
      importedAt: DateTime.utc(2026),
    ),
    raw ?? _png(image),
  );
  return repo;
}

/// Selfie Multiclass stand-in: the left half of the tensor is hair, the
/// right half face skin (as logits).
FakeInferenceSession _fakeSession() => FakeInferenceSession(
  _spec.fileName,
  FakeModel.fromSpec(_spec, (inputs) {
    final out = Float32List(256 * 256 * 6);
    for (var y = 0; y < 256; y++) {
      for (var x = 0; x < 256; x++) {
        out[(y * 256 + x) * 6 + (x < 128 ? 1 : 3)] = 6;
      }
    }
    return {'Identity': out};
  }),
);

Future<T> _inline<T>(FutureOr<T> Function() fn) async => fn();

class _CountingParser implements FaceParser {
  _CountingParser(this.inner);
  final FaceParser inner;
  int runs = 0;

  @override
  ModelSpec get spec => inner.spec;

  @override
  Future<List<FaceParsingPlanes>> parse(List<FaceTileImage> tiles) {
    runs++;
    return inner.parse(tiles);
  }

  @override
  Future<void> dispose() => inner.dispose();
}

/// A session whose runs return no tensors at all.
class _NoOutputSession implements InferenceSession {
  _NoOutputSession(this.inner);
  final InferenceSession inner;

  @override
  List<TensorSignature> get inputs => inner.inputs;

  @override
  List<TensorSignature> get outputs => inner.outputs;

  @override
  Future<Map<String, Float32List>> run(Map<String, Float32List> inputs) async =>
      const {};

  @override
  Future<void> dispose() => inner.dispose();
}

class _BrokenCache implements FaceParsingCache {
  @override
  Future<Uint8List?> read(String assetId) =>
      Future.error(const FileSystemException('no disk'));
  @override
  Future<void> write(String assetId, Uint8List bytes) =>
      Future.error(const FileSystemException('no disk'));
  @override
  Future<void> delete(String assetId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The "original" is twice the size of the face analysis decode.
  final full = renderSynthPortrait(640, 560, const [
    SynthFace(id: 'f', cx: 320, cy: 230, iod: 160),
  ]);

  group('full-resolution face tiles', () {
    test('crops the planned window of the pixel source', () async {
      final repo = await _catalog(full.image);
      final tiles = await loadFaceTiles(repo, _id, full.analysis);
      expect(tiles, hasLength(1));
      final t = tiles.single;
      expect(t.plan.gridW, 640, reason: 'IOD 160 < 224: native size');
      // Native size: a texel-exact copy of the window.
      final ref = resampleTile(full.image, t.plan);
      var worst = 0;
      for (var i = 0; i < ref.data.length; i++) {
        final d = (ref.data[i] - t.pixels.data[i]).abs();
        if (d > worst) worst = d;
      }
      expect(worst, lessThanOrEqualTo(1));
    });

    test('large faces are cropped down to the target IOD', () async {
      final big = renderSynthPortrait(900, 800, const [
        SynthFace(id: 'f', cx: 450, cy: 300, iod: 336),
      ]);
      final repo = await _catalog(big.image);
      final t = (await loadFaceTiles(repo, _id, big.analysis)).single;
      expect(t.plan.gridW / 900, closeTo(kTileTargetIod / 336, 0.01));
      final ref = resampleTile(big.image, t.plan);
      var sum = 0.0;
      for (var i = 0; i < ref.data.length; i += 4) {
        sum += (ref.data[i] - t.pixels.data[i]).abs();
      }
      expect(sum / (ref.data.length / 4), lessThan(4));
    });

    test(
      'skipped faces, no faces and undecodable sources give no tiles',
      () async {
        final repo = await _catalog(full.image);
        expect(
          await loadFaceTiles(repo, _id, full.analysis, skip: {'f'}),
          isEmpty,
        );
        final bad = await _catalog(
          full.image,
          raw: Uint8List.fromList([1, 2, 3]),
        );
        expect(await loadFaceTiles(bad, _id, full.analysis), isEmpty);
      },
    );

    test('faces with a heal on them fall back to the decode', () {
      const heal = HealOp(
        id: 'h',
        bbox: PixelBox(300, 250, 320, 270),
        srcWidth: 640,
        srcHeight: 560,
        patch: 'retouch/h.png',
      );
      final plans = planFaceTiles(full.analysis, 640, 560);
      final tiles = [
        FaceTileImage(plans.single, resampleTile(full.image, plans.single)),
      ];
      expect(facesWithHeals(const [heal], full.analysis), {'f'});
      expect(tilesWithoutHeals(tiles, const [heal], full.analysis), isEmpty);
      expect(tilesWithoutHeals(tiles, const [], full.analysis), tiles);
    });
  });

  group('FaceParser', () {
    test('parses every tile into planes over its source rect', () async {
      final parser = FaceParser(
        session: _fakeSession(),
        spec: _spec,
        runner: _inline,
      );
      final plans = planFaceTiles(full.analysis, 640, 560);
      final tile = FaceTileImage(
        plans.single,
        resampleTile(full.image, plans.single),
      );
      final planes = (await parser.parse([tile])).single;
      expect(planes.faceId, 'f');
      expect(planes.cropX, closeTo(plans.single.u0, 1e-12));
      expect(
        planes.cropWidth,
        closeTo(plans.single.u1 - plans.single.u0, 1e-12),
      );
      // The letterbox is cut away: the planes keep the tile's aspect.
      expect(
        planes.width / planes.height,
        closeTo(tile.plan.width / tile.plan.height, 0.05),
      );
      expect(planes.hair[planes.width ~/ 4], greaterThan(250));
      expect(planes.faceSkin[planes.width - 2], greaterThan(250));
      await parser.dispose();
    });

    test('a model without a ≥5-class output is refused', () {
      final bad = FakeInferenceSession(
        'bad',
        const FakeModel(
          inputs: [
            (name: 'input_29', shape: [1, 256, 256, 3]),
          ],
          outputs: [
            (name: 'Identity', shape: [1, 256, 256, 2]),
          ],
          onRun: _none,
        ),
      );
      expect(
        () => FaceParser(session: bad, spec: _spec),
        throwsA(isA<ModelContractMismatch>()),
      );
    });

    test('a run without output fails typed', () async {
      final parser = FaceParser(
        session: _NoOutputSession(_fakeSession()),
        spec: _spec,
        runner: _inline,
      );
      final plans = planFaceTiles(full.analysis, 640, 560);
      await expectLater(
        parser.parse([
          FaceTileImage(plans.single, resampleTile(full.image, plans.single)),
        ]),
        throwsA(isA<InferenceRunFailed>()),
      );
    });
  });

  group('cache format', () {
    final plans = planFaceTiles(full.analysis, 640, 560);
    final planes = [synthParsing(full, plans.single)];
    final key = faceParsingKey(_spec, plans);

    test('round-trips under its key only', () {
      final bytes = wrapParsing(key, planes);
      expect(unwrapParsing(bytes, key)!.single.hair, planes.single.hair);
      expect(unwrapParsing(bytes, '$key!'), isNull);
      expect(unwrapParsing(Uint8List(2), key), isNull);
      expect(unwrapParsing(bytes.sublist(0, 6), key), isNull);
      final badKey = Uint8List.fromList(bytes)..[4] = 0xff;
      expect(unwrapParsing(badKey, key), isNull);
      // Another plan (other tile window) is another key.
      final moved = FaceTilePlan(
        slot: 0,
        faceId: 'f',
        gridW: plans.single.gridW,
        gridH: plans.single.gridH,
        window: MapRect(
          plans.single.window.x0 + 1,
          plans.single.window.y0,
          plans.single.window.w,
          plans.single.window.h,
        ),
      );
      expect(faceParsingKey(_spec, [moved]), isNot(key));
    });

    test('FileFaceParsingCache keeps it in the backup-excluded face cache '
        'folder', () async {
      final tmp = await Directory.systemTemp.createTemp('parsing_cache');
      addTearDown(() => tmp.delete(recursive: true));
      final excluded = <String>[];
      const channel = MethodChannel('lumen/backup');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            excluded.add((call.arguments as Map)['path'] as String);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const mac = PlatformInfo(
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        isIOS: false,
        isAndroid: false,
      );
      final cache = FileFaceParsingCache(tmp.path, platform: mac);
      const asset = '0123456789abcdef0123456789abcdef';
      expect(await cache.read(asset), isNull);
      final bytes = wrapParsing(key, planes);
      await cache.write(asset, bytes);
      await pumpEventQueue();
      expect(
        cache.pathFor(asset),
        p.join(tmp.path, 'assets', asset, kAssetCacheDir, kFaceParsingFile),
      );
      expect(await cache.read(asset), bytes);
      expect(excluded.map((e) => p.relative(e, from: tmp.path)), [
        p.join('assets', asset, kAssetCacheDir),
      ]);
      await cache.delete(asset);
      expect(await cache.read(asset), isNull);
      await cache.delete(asset);
      expect(() => cache.pathFor('../x'), throwsArgumentError);
    });

    test('MemoryFaceParsingCache', () async {
      final cache = MemoryFaceParsingCache();
      await cache.write(_id, Uint8List(3));
      expect(await cache.read(_id), hasLength(3));
      await cache.delete(_id);
      expect(await cache.read(_id), isNull);
    });
  });

  group('FaceParsingService', () {
    late List<FaceTileImage> tiles;
    setUp(() {
      final plans = planFaceTiles(full.analysis, 640, 560);
      tiles = [
        FaceTileImage(plans.single, resampleTile(full.image, plans.single)),
      ];
    });

    test('parses once, then serves the cache', () async {
      final cache = MemoryFaceParsingCache();
      final parser = _CountingParser(
        FaceParser(session: _fakeSession(), spec: _spec, runner: _inline),
      );
      final downloads = <bool>[];
      final service = FaceParsingService(
        cache: () async => cache,
        parser: ({bool download = true}) async {
          downloads.add(download);
          return parser;
        },
      );
      final first = await service.parse(_id, tiles);
      expect(first, hasLength(1));
      expect(parser.runs, 1);
      final again = await service.parse(_id, tiles, download: false);
      expect(again!.single.hair, first!.single.hair);
      expect(parser.runs, 1, reason: 'cache hit');
      expect(downloads, [true]);
      expect(await service.cached(_id, const []), isNull);
    });

    test('no model, a failed run or a broken cache never throw', () async {
      final none = FaceParsingService(
        cache: () async => MemoryFaceParsingCache(),
        parser: ({bool download = true}) async => null,
      );
      expect(await none.parse(_id, tiles, download: false), isNull);
      expect(await none.parse(_id, const []), isNull);
      final failing = FaceParsingService(
        cache: () async => MemoryFaceParsingCache(),
        parser: ({bool download = true}) =>
            Future.error(const InferenceUnavailable('offline')),
      );
      expect(await failing.parse(_id, tiles), isNull);
      // A cache that cannot be read or written still parses.
      final noDisk = FaceParsingService(
        cache: () async => _BrokenCache(),
        parser: ({bool download = true}) async =>
            FaceParser(session: _fakeSession(), spec: _spec, runner: _inline),
      );
      expect(await noDisk.parse(_id, tiles), hasLength(1));
    });
  });

  group('retouch maps', () {
    final decode = renderSynthPortrait(320, 280, const [
      SynthFace(id: 'f', cx: 160, cy: 115, iod: 80),
    ]);

    test('use full-resolution tiles at once and rebuild when parsing '
        'arrives; failed parsing keeps the heuristic', () async {
      final repo = await _catalog(full.image);
      final parsing = Completer<List<FaceParsingPlanes>?>();
      final c = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          faceAnalysisProvider(_id).overrideWith(
            (ref) async =>
                FaceCacheEntry(models: kFaceModels, analysis: decode.analysis),
          ),
          faceParsingProvider(_id).overrideWith((ref) => parsing.future),
        ],
      );
      addTearDown(c.dispose);
      await c.read(editorProvider(_id).future);
      final sub = c.listen(retouchBaseMapsProvider(_id), (_, _) {});
      addTearDown(sub.close);
      final first = (await c.read(retouchBaseMapsProvider(_id).future))!;
      // The face is analysed on its full-resolution tile.
      expect(first.maps.faces.single.iod, closeTo(160, 1));
      final plans = planFaceTiles(decode.analysis, 640, 560);
      parsing.complete([synthParsing(full, plans.single)]);
      await pumpEventQueue();
      final second = (await c.read(retouchBaseMapsProvider(_id).future))!;
      expect(identical(second.maps, first.maps), isFalse);
      expect(second.maps.regionA, isNot(first.maps.regionA));
    });

    test('without parsing the maps are the heuristic ones', () async {
      final repo = await _catalog(full.image);
      final c = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          faceAnalysisProvider(_id).overrideWith(
            (ref) async =>
                FaceCacheEntry(models: kFaceModels, analysis: decode.analysis),
          ),
          faceParsingProvider(_id).overrideWith((ref) async => null),
        ],
      );
      addTearDown(c.dispose);
      await c.read(editorProvider(_id).future);
      final sub = c.listen(retouchBaseMapsProvider(_id), (_, _) {});
      addTearDown(sub.close);
      final got = (await c.read(retouchBaseMapsProvider(_id).future))!;
      final tiles = await c.read(faceTilesProvider(_id).future);
      expect(tiles, hasLength(1));
      final want = computeRetouchMaps(
        full.image,
        decode.analysis,
        tiles: tiles,
      );
      expect(got.maps.regionA, want.regionA);
    });
  });
}

Map<String, Float32List> _none(Map<String, Float32List> inputs) => const {};
