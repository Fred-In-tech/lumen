import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_cache_io.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'face_fakes.dart';

const _id = '0123456789abcdef0123456789abcdef';

FaceCacheEntry _entry({String mesh = 'mesh@1'}) => FaceCacheEntry(
  models: {'detector': 'det@1', 'mesh': mesh},
  analysis: const FaceAnalysis(
    imageWidth: 400,
    imageHeight: 300,
    modelVersion: 'det@1+mesh@1',
    faces: [
      DetectedFace(
        id: 'f32_32',
        box: FaceBox(0.4, 0.4, 0.2, 0.2),
        landmarks: [0.5, 0.5, 0.6, 0.5],
        confidence: 0.9,
      ),
    ],
  ),
  rejected: const [
    RejectedFace(
      id: 'f10_10',
      box: FaceBox(0.1, 0.1, 0.05, 0.05),
      reason: FaceRejectReason.tooSmall,
    ),
  ],
);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('face_cache'));
  tearDown(() => tmp.delete(recursive: true));

  group('FileFaceCache', () {
    test('round-trips under assets/<id>/cache/face.json', () async {
      final cache = FileFaceCache(tmp.path);
      final e = _entry();
      await cache.write(_id, e);

      final path = p.join(tmp.path, 'assets', _id, 'cache', 'face.json');
      expect(cache.pathFor(_id), path);
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse);

      final back = await FileFaceCache(tmp.path).read(_id);
      expect(back, isNotNull);
      expect(back!.analysis, e.analysis);
      expect(back.rejected, e.rejected);
      expect(back.models, e.models);
      expect(
        back.matchesModels({'detector': 'det@1', 'mesh': 'mesh@1'}),
        isTrue,
      );
      expect(
        back.matchesModels({'detector': 'det@2', 'mesh': 'mesh@1'}),
        isFalse,
      );

      await cache.delete(_id);
      expect(await cache.read(_id), isNull);
    });

    test('corrupt or other-version files read as a miss', () async {
      final cache = FileFaceCache(tmp.path);
      final f = File(cache.pathFor(_id))..createSync(recursive: true);
      f.writeAsStringSync('{not json');
      expect(await cache.read(_id), isNull);
      f.writeAsStringSync(jsonEncode({'cacheVersion': 99}));
      expect(await cache.read(_id), isNull);
    });

    test('asset ids that could escape the folder are rejected', () {
      final cache = FileFaceCache(tmp.path);
      for (final bad in ['../x', 'a/b', '', r'a\b', '..']) {
        expect(() => cache.pathFor(bad), throwsArgumentError, reason: bad);
      }
    });

    test('deleting the photo deletes its face cache', () async {
      final catalog = FileCatalogRepository(tmp.path);
      await catalog.add(
        CatalogEntry(
          assetId: _id,
          fileName: 'x.jpg',
          originalPath: 'originals/$_id.jpg',
          format: 'jpeg',
          width: 4,
          height: 3,
          bytes: 3,
          importedAt: DateTime.utc(2026, 10, 3),
        ),
        Uint8List.fromList([1, 2, 3]),
      );
      final cache = FileFaceCache(tmp.path);
      await cache.write(_id, _entry());
      await catalog.delete(_id);
      expect(File(cache.pathFor(_id)).existsSync(), isFalse);
    });
  });

  group('FaceAnalysisService', () {
    const w = 400, h = 300;
    final pixels = RgbaBuffer.filled(w, h, 100, 100, 100);

    FaceAnalysisService service(
      FaceCache cache, {
      Map<String, String>? models,
    }) {
      final backend = fakeFaceBackend(
        faces: [(cx: 0.5, cy: 0.5, size: 0.25)],
        w: w,
        h: h,
      );
      final models0 = {'detector': detSpec.key, 'mesh': meshSpec.key};
      return FaceAnalysisService(
        cache: cache,
        models: models ?? models0,
        analyzer: () => fakeAnalyzer(backend),
      );
    }

    test('analyzes once, then serves the cache; tags persist', () async {
      final cache = FileFaceCache(tmp.path);
      final svc = service(cache);
      var loads = 0;
      Future<RgbaBuffer> load() async {
        loads++;
        return pixels;
      }

      final first = await svc.analyze(_id, pixels: load);
      expect(first.analysis.faces, hasLength(1));
      expect(await svc.analyze(_id, pixels: load), isNotNull);
      expect(loads, 1);
      expect(await svc.cached(_id), isNotNull);

      final faceId = first.analysis.faces.single.id;
      final tagged = await svc.tag(
        _id,
        faceId,
        FaceGroup.senior,
        personId: 'p7',
      );
      expect(tagged!.analysis.faceById(faceId)!.tagSource, TagSource.manual);
      expect(await svc.tag(_id, 'nope', FaceGroup.male), isNull);

      final reread = await FileFaceCache(tmp.path).read(_id);
      final f = reread!.analysis.faceById(faceId)!;
      expect(f.group, FaceGroup.senior);
      expect(f.personId, 'p7');
    });

    test('a model change re-analyzes and keeps manual tags', () async {
      final cache = MemoryFaceCache();
      final first = await service(cache)
          .analyze(_id, pixels: () async => pixels);
      final faceId = first.analysis.faces.single.id;
      await service(cache).tag(_id, faceId, FaceGroup.child);
      // Stored with the old key: the service sees a stale entry.
      final stale = (await cache.read(_id))!;
      await cache.write(
        _id,
        FaceCacheEntry(
          models: const {'detector': 'old@0', 'mesh': 'old@0'},
          analysis: stale.analysis,
        ),
      );
      final svc = service(cache);
      expect(await svc.cached(_id), isNull);

      final rerun = await svc.analyze(_id, pixels: () async => pixels);

      expect(rerun.models, svc.models);
      expect(rerun.analysis.faceById(faceId)!.group, FaceGroup.child);
    });
  });
}
