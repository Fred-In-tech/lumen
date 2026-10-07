import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/import/float_decoder_types.dart';
import 'package:lumen/import/float_preview_cache_io.dart';
import 'package:lumen/import/float_preview_cache_types.dart';
import 'package:lumen/import/float_preview_store.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/raw_developer.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import '../support/fake_float_preview.dart';
import '../support/fixtures.dart';

/// Float previews in memory and on disk (docs/HIGH_BIT_DEPTH.md, "Preview
/// cache"): a photo is decoded once, reopened from the cache, and the
/// filmstrip neighbours are prepared in the background.

class _FakeRaw implements RawDeveloper {
  @override
  Future<Uint8List> develop(Uint8List raw, {required String extension}) async =>
      Fixtures.jpeg(w: 60, h: 40);
}

/// A cache that records what was kept on trim.
class _SpyCache implements FloatPreviewCache {
  _SpyCache(this.inner);
  final FloatPreviewCache inner;
  final List<Set<String>> trims = [];

  @override
  Future<bool> contains(String assetId, int width, int height) =>
      inner.contains(assetId, width, height);
  @override
  Future<FloatSourceInfo?> infoFor(String assetId) => inner.infoFor(assetId);
  @override
  Future<String?> pathFor(String assetId, int width, int height) =>
      inner.pathFor(assetId, width, height);
  @override
  Future<void> remove(String assetId) => inner.remove(assetId);
  @override
  Future<int> sizeInBytes() => inner.sizeInBytes();
  @override
  Future<void> touch(String path) => inner.touch(path);
  @override
  Future<int> trim({Set<String> keep = const {}}) {
    trims.add(keep);
    return inner.trim(keep: keep);
  }
}

void main() {
  late Directory root;
  late FakeCachingDecoder decoder;
  late _SpyCache cache;
  late FloatPreviewStore store;

  DecodedFloatSource source(String path) => DecodedFloatSource(
    decoder,
    path,
    const FloatSourceInfo(
      width: 600,
      height: 400,
      profile: HbdProfile.rawExtended,
    ),
  );

  FloatPreviewTarget target(String id) => FloatPreviewTarget(
    assetId: id,
    path: '/originals/$id.cr3',
    width: 6,
    height: 4,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('lumen_fps');
    decoder = FakeCachingDecoder();
    cache = _SpyCache(
      FileFloatPreviewCache(() async => p.join(root.path, 'previews')),
    );
    store = FloatPreviewStore(decoder: decoder, cache: cache);
  });
  tearDown(() {
    store.dispose();
    root.deleteSync(recursive: true);
  });

  group('FloatPreviewStore', () {
    test('decodes once, then memory, then the disk cache', () async {
      expect(await store.cached('a', 6, 4), isNull);
      final first = await store.load('a', source('/o/a.cr3'), 6, 4);
      expect(decoder.renders, ['/o/a.cr3']);
      expect(await cache.contains('a', 6, 4), isTrue);
      // Memory: the same pixels, no read.
      expect(
        identical(await store.load('a', source('/o/a.cr3'), 6, 4), first),
        isTrue,
      );
      expect(decoder.reads, isEmpty);
      // A new session (memory dropped): the disk entry, no decode.
      store.clearMemory();
      final again = await store.load('a', source('/o/a.cr3'), 6, 4);
      expect(decoder.renders, hasLength(1));
      expect(decoder.reads, hasLength(1));
      expect(again.rgba, first.rgba);
      expect(store.decodes, 1);
    });

    test('concurrent loads share one decode', () async {
      final results = await Future.wait([
        store.load('a', source('/o/a.cr3'), 6, 4),
        store.load('a', source('/o/a.cr3'), 6, 4),
      ]);
      expect(identical(results[0], results[1]), isTrue);
      expect(decoder.renders, hasLength(1));
    });

    test('a failed decode throws and caches nothing', () async {
      decoder.failRender = true;
      await expectLater(
        store.load('a', source('/o/a.cr3'), 6, 4),
        throwsA(isA<FloatSourceException>()),
      );
      expect(await cache.contains('a', 6, 4), isFalse);
      expect(store.memoryKeys, isEmpty);
    });

    test('memory keeps the three most recently used previews', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await store.load(id, source('/o/$id.cr3'), 6, 4);
      }
      expect(store.memoryKeys, ['b@6x4', 'c@6x4', 'd@6x4']);
      await store.cached('b', 6, 4); // used again
      await store.load('e', source('/o/e.cr3'), 6, 4);
      expect(store.memoryKeys, ['d@6x4', 'b@6x4', 'e@6x4']);
    });

    test(
      'prefetch builds missing entries and loads them into memory',
      () async {
        await store.load('a', source('/o/a.cr3'), 6, 4);
        store.prefetch([target('b'), target('c')]);
        await store.idle();
        expect(decoder.builds, ['/originals/b.cr3', '/originals/c.cr3']);
        expect(store.memoryKeys, ['a@6x4', 'b@6x4', 'c@6x4']);
        // Stepping to b: no decode, no read.
        final reads = decoder.reads.length;
        await store.load('b', source('/originals/b.cr3'), 6, 4);
        expect(decoder.reads.length, reads);
        expect(decoder.renders, hasLength(1));
        // Already cached and in memory: nothing more to build.
        store.prefetch([target('c')]);
        await store.idle();
        expect(decoder.builds, hasLength(2));
      },
    );

    test('prefetch keeps at most two neighbours and replaces older '
        'requests', () async {
      final gate = Completer<void>();
      decoder.buildGate = gate.future;
      store.prefetch([target('a'), target('b'), target('c')]);
      while (decoder.builds.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      // `a` is building; the user moved on: `b` is dropped for `x`, `y`.
      store.prefetch([target('x'), target('y')]);
      gate.complete();
      await store.idle();
      expect(decoder.builds, [
        '/originals/a.cr3',
        '/originals/x.cr3',
        '/originals/y.cr3',
      ]);
    });

    test('warm builds entries without filling memory', () async {
      store.warm([target('a'), target('b'), target('a')]);
      await store.idle();
      expect(decoder.builds, ['/originals/a.cr3', '/originals/b.cr3']);
      expect(store.memoryKeys, isEmpty);
      expect(await cache.contains('b', 6, 4), isTrue);
      // A failed build is skipped quietly.
      decoder.failRender = true;
      store.warm([target('z')]);
      await store.idle();
      expect(await cache.contains('z', 6, 4), isFalse);
    });

    test('a load waits for the background build of the same preview', () async {
      final gate = Completer<void>();
      decoder.buildGate = gate.future;
      store.warm([target('a')]);
      while (decoder.builds.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final load = store.load('a', source('/originals/a.cr3'), 6, 4);
      gate.complete();
      await load;
      expect(decoder.renders, isEmpty, reason: 'served by the build');
      expect(decoder.builds, hasLength(1));
    });

    test(
      'the folder is trimmed after writes, keeping what is in memory',
      () async {
        await store.load('a', source('/o/a.cr3'), 6, 4);
        await Future<void>.delayed(
          FloatPreviewStore.trimDelay + const Duration(milliseconds: 50),
        );
        expect(cache.trims, hasLength(1));
        expect(cache.trims.single, {(await cache.pathFor('a', 6, 4))!});
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('without a cache folder it still decodes, never builds', () async {
      final bare = FloatPreviewStore(
        decoder: decoder,
        cache: const NoFloatPreviewCache(),
      );
      addTearDown(bare.dispose);
      await bare.load('a', source('/o/a.cr3'), 6, 4);
      bare.warm([target('b')]);
      await bare.idle();
      expect(decoder.renders, hasLength(1));
      expect(decoder.builds, isEmpty);
    });
  });

  group('CachingFloatSource', () {
    test('whole-photo renders go through the store, windows do not', () async {
      final s = CachingFloatSource(
        assetId: 'a',
        inner: source('/o/a.cr3'),
        store: store,
      );
      expect(
        (s.width, s.height, s.profile),
        (600, 400, HbdProfile.rawExtended),
      );
      expect(await s.cachedPreview(6, 4), isNull);
      await s.render(fullWidth: 6, fullHeight: 4);
      expect(await s.cachedPreview(6, 4), isNotNull);
      final window = await s.render(
        fullWidth: 6,
        fullHeight: 4,
        x: 1,
        width: 2,
        height: 2,
      );
      expect((window.width, window.height), (2, 2));
      expect(decoder.renders, hasLength(2));
      await s.release();
      expect(decoder.released, ['/o/a.cr3']);
    });
  });

  group('FloatSources with a store', () {
    late FileCatalogRepository catalog;
    late FloatSources sources;

    setUp(() {
      catalog = FileCatalogRepository(p.join(root.path, 'catalog'));
      sources = FloatSources(catalog: catalog, decoder: decoder, store: store);
    });

    Future<String> importRaw(int seed) async {
      final r = await ImportService(catalog, rawDeveloper: _FakeRaw())
          .importOne(
            ImportFile(
              name: 'p$seed.cr3',
              bytes: Fixtures.cr3(seed: seed),
            ),
          );
      return (r as Imported).entry.assetId;
    }

    test('a cached photo opens from the header, without the decoder', () async {
      final id = await importRaw(1);
      final first = await sources.open(id);
      expect(first, isA<CachingFloatSource>());
      expect(decoder.infos, hasLength(1));
      await first!.render(fullWidth: 60, fullHeight: 40);
      decoder.infos.clear();
      store.clearMemory();
      final again = await sources.open(id);
      expect(decoder.infos, isEmpty, reason: 'info came from the cache file');
      expect((again!.width, again.height), (600, 400));
      expect(
        await (again as PreviewCacheAware).cachedPreview(60, 40),
        isNotNull,
      );
      expect(decoder.renders, hasLength(1));
    });

    test('targets: float photos at the editor preview size', () async {
      final raw = await importRaw(2);
      final jpg = (await ImportService(catalog).importOne(
        ImportFile(name: 'x.jpg', bytes: Fixtures.jpeg(seed: 3)),
      ) as Imported).entry.assetId;
      final t = await sources.targets([
        raw,
        jpg,
        'missing',
      ], previewLongEdge: 30);
      expect(t.map((e) => e.assetId), [raw]);
      expect((t.single.width, t.single.height), (30, 20));
      expect(t.single.path, await catalog.originalFilePath(raw));
    });

    test('prefetch and warm reach the store', () async {
      final a = await importRaw(4);
      final b = await importRaw(5);
      await sources.prefetch([a], previewLongEdge: 30);
      await store.idle();
      expect(store.memoryKeys, ['$a@30x20']);
      await sources.warm([b], previewLongEdge: 30);
      await store.idle();
      expect(await cache.contains(b, 30, 20), isTrue);
      // Nothing to do: no store, or no photos.
      final plain = FloatSources(catalog: catalog, decoder: decoder);
      await plain.prefetch([a], previewLongEdge: 30);
      await plain.warm([a], previewLongEdge: 30);
      await sources.prefetch(const [], previewLongEdge: 30);
      expect(decoder.builds, hasLength(2));
    });
  });
}
