import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/features/info/photo_info.dart';
import 'package:lumen/import/float_decoder_io.dart';
import 'package:lumen/import/float_decoder_types.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/raw_developer.dart';
import 'package:lumen/platform/platform_info_io.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/fixtures.dart';

/// Which photos get a float source (docs/HIGH_BIT_DEPTH.md §Sources), the
/// `lumen/raw` float channel contract, and what the info panel says.

Uint8List _png16({int w = 32, int h = 16}) {
  final image = img.Image(
    width: w,
    height: h,
    numChannels: 3,
    format: img.Format.uint16,
  );
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x * 2000, y * 4000, 30000);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _FakeRaw implements RawDeveloper {
  @override
  Future<Uint8List> develop(Uint8List raw, {required String extension}) async =>
      Fixtures.jpeg(w: 60, h: 40);
}

class _FakeDecoder implements FloatDecoder {
  final List<String> infos = [], released = [];
  bool decodable = true;

  @override
  Future<FloatSourceInfo?> info(String path) async {
    infos.add(path);
    return decodable
        ? const FloatSourceInfo(
            width: 60,
            height: 40,
            profile: HbdProfile.rawExtended,
          )
        : null;
  }

  @override
  Future<FloatPixels> render(
    String path, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
    String? cachePath,
  }) async => FloatPixels(
    width,
    height,
    Float32List(width * height * 4)..fillRange(0, width * height * 4, 0.5),
  );

  @override
  Future<void> release(String path) async => released.add(path);

  @override
  Future<CachedFloatPreview?> readPreview(
    String cachePath, {
    required int width,
    required int height,
  }) async => null;

  @override
  Future<int?> buildPreview(
    String path, {
    required String cachePath,
    required int fullWidth,
    required int fullHeight,
  }) async => null;
}

const _mac = PlatformInfo(
  isMacOS: true,
  isWindows: false,
  isLinux: false,
  isIOS: false,
  isAndroid: false,
);
const _windows = PlatformInfo(
  isMacOS: false,
  isWindows: true,
  isLinux: false,
  isIOS: false,
  isAndroid: false,
);

CatalogEntry _entry(String format, {int? bitDepth}) => CatalogEntry(
  assetId: 'a',
  fileName: 'a.$format',
  originalPath: 'originals/a.$format',
  format: format,
  width: 100,
  height: 50,
  bytes: 10,
  importedAt: DateTime.utc(2026),
  bitDepth: bitDepth,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatSources', () {
    late Directory root;
    late FileCatalogRepository catalog;
    late _FakeDecoder decoder;
    late FloatSources sources;

    setUp(() {
      root = Directory.systemTemp.createTempSync('lumen_float_sources');
      catalog = FileCatalogRepository(root.path);
      decoder = _FakeDecoder();
      sources = FloatSources(catalog: catalog, decoder: decoder);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<CatalogEntry> import(String name, Uint8List bytes) async {
      final r = await ImportService(
        catalog,
        rawDeveloper: _FakeRaw(),
      ).importOne(ImportFile(name: name, bytes: bytes));
      return (r as Imported).entry;
    }

    test(
      'a 16-bit PNG: depth recorded at import, float source by path',
      () async {
        final entry = await import('deep.png', _png16());
        expect(entry.bitDepth, 16);
        final path = await catalog.originalFilePath(entry.assetId);
        expect(File(path!).existsSync(), isTrue);
        final source = await sources.open(entry.assetId);
        expect(source, isNotNull);
        expect(decoder.infos, [path]);
        expect((source!.width, source.height), (60, 40));
        expect(source.profile, HbdProfile.rawExtended);
        final px = await source.render(fullWidth: 30, fullHeight: 20, x: 2);
        expect((px.width, px.height), (28, 20));
        await source.release();
        expect(decoder.released, [path]);
      },
    );

    test('8-bit photos have none and never reach the decoder', () async {
      final png = await import('flat.png', Fixtures.png());
      final jpg = await import('p.jpg', Fixtures.jpeg(seed: 4));
      expect(png.bitDepth, 8);
      expect(jpg.bitDepth, 8);
      expect(await sources.open(png.assetId), isNull);
      expect(await sources.open(jpg.assetId), isNull);
      expect(await sources.open('missing'), isNull);
      expect(decoder.infos, isEmpty);
    });

    test('camera RAW always qualifies, whatever depth it declares', () async {
      final entry = await import('a.cr3', Fixtures.cr3());
      expect(entry.bitDepth, isNull);
      expect(bitDepthLabel(entry), 'RAW');
      expect(await sources.open(entry.assetId), isNotNull);
      // A file the system cannot decode in float: back to the 8-bit path.
      decoder.decodable = false;
      expect(await sources.open(entry.assetId), isNull);
    });

    test(
      'catalogs from before bitDepth: PNG is sniffed from its header',
      () async {
        final bytes = _png16();
        final id = ImportService.assetIdFor(bytes);
        await catalog.add(
          CatalogEntry(
            assetId: id,
            fileName: 'old.png',
            originalPath: 'originals/$id.png',
            format: 'png',
            width: 32,
            height: 16,
            bytes: bytes.length,
            importedAt: DateTime.utc(2025),
          ),
          bytes,
        );
        expect((await catalog.get(id))!.bitDepth, isNull);
        expect(await sources.open(id), isNotNull);
      },
    );

    test('a missing original gives no source', () async {
      final entry = await import('deep.png', _png16());
      File((await catalog.originalFilePath(entry.assetId))!).deleteSync();
      expect(await catalog.originalFilePath(entry.assetId), isNull);
      expect(await sources.open(entry.assetId), isNull);
      expect(await catalog.originalFilePath('nope'), isNull);
    });

    test('catalogs without files (web, tests) keep the 8-bit path', () async {
      final memory = MemoryCatalogRepository();
      final r = await ImportService(memory)
          .importOne(ImportFile(name: 'deep.png', bytes: _png16()));
      final id = (r as Imported).entry.assetId;
      expect(memory, isNot(isA<OriginalFileLocator>()));
      expect(
        await FloatSources(catalog: memory, decoder: decoder).open(id),
        isNull,
      );
    });

    test('floatEditingProvider: a source and a capable device', () async {
      final deep = await import('deep.png', _png16());
      final flat = await import('flat.png', Fixtures.png());
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(catalog),
          floatDecoderProvider.overrideWithValue(decoder),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(HbdCapability.reset);
      HbdCapability.override = true;
      expect(
        await container.read(floatEditingProvider(deep.assetId).future),
        isTrue,
      );
      expect(
        await container.read(floatEditingProvider(flat.assetId).future),
        isFalse,
      );
      HbdCapability.override = false;
      container.invalidate(floatEditingProvider(deep.assetId));
      expect(
        await container.read(floatEditingProvider(deep.assetId).future),
        isFalse,
      );
    });
  });

  group('PlatformFloatDecoder (lumen/raw float methods)', () {
    const channel = MethodChannel('lumen/raw');
    final calls = <MethodCall>[];
    Object? Function(MethodCall call)? reply;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return reply!(call);
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('floatInfo maps the size and the profile', () async {
      reply = (_) => {
        'width': 5464,
        'height': 8192,
        'shoulderKnee': 0.86,
        'highlightGain': 0.5,
      };
      final info = await const PlatformFloatDecoder(platform: _mac)
          .info('/x/a.cr3');
      expect((info!.width, info.height), (5464, 8192));
      expect(info.profile, HbdProfile.rawExtended);
      expect(calls.single.method, 'floatInfo');
      expect(calls.single.arguments, {'input': '/x/a.cr3'});
    });

    test('no decoder: other platforms, errors and empty answers', () async {
      reply = (_) => {'width': 0, 'height': 0};
      expect(
        await const PlatformFloatDecoder(platform: _mac).info('/x/a.png'),
        isNull,
      );
      reply = (_) => throw PlatformException(code: 'float_failed');
      expect(
        await const PlatformFloatDecoder(platform: _mac).info('/x/a.png'),
        isNull,
      );
      calls.clear();
      expect(
        await const PlatformFloatDecoder(platform: _windows).info('/x/a.cr3'),
        isNull,
      );
      await const PlatformFloatDecoder(platform: _windows).release('/x/a.cr3');
      expect(calls, isEmpty, reason: 'no channel call off Apple platforms');
    });

    test(
      'floatRender passes the window and returns the float pixels',
      () async {
        final pixels = Float32List.fromList([4, 0.5, -0.1, 1, 0, 0, 0, 1]);
        reply = (_) => {'pixels': pixels, 'ms': 12};
        const decoder = PlatformFloatDecoder(platform: _mac);
        final px = await decoder.render(
          '/x/a.cr3',
          fullWidth: 100,
          fullHeight: 50,
          x: 10,
          y: 20,
          width: 2,
          height: 1,
        );
        expect(px.rgba, pixels);
        expect(px.decodeMs, 12);
        expect(calls.single.arguments, {
          'input': '/x/a.cr3',
          'fullWidth': 100,
          'fullHeight': 50,
          'x': 10,
          'y': 20,
          'width': 2,
          'height': 1,
        });
        // The wrong amount of data and native failures are decode errors.
        await expectLater(
          decoder.render(
            '/x/a.cr3',
            fullWidth: 100,
            fullHeight: 50,
            x: 0,
            y: 0,
            width: 3,
            height: 1,
          ),
          throwsA(isA<FloatSourceException>()),
        );
        reply = (_) =>
            throw PlatformException(code: 'float_failed', message: 'x');
        await expectLater(
          decoder.render(
            '/x/a.cr3',
            fullWidth: 1,
            fullHeight: 1,
            x: 0,
            y: 0,
            width: 1,
            height: 1,
          ),
          throwsA(isA<FloatSourceException>()),
        );
      },
    );

    test('floatRender with a cache path asks for the cache entry', () async {
      reply = (_) => {'pixels': Float32List(4)};
      await const PlatformFloatDecoder(platform: _mac).render(
        '/x/a.cr3',
        fullWidth: 1,
        fullHeight: 1,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        cachePath: '/c/a.lfp',
      );
      expect((calls.single.arguments as Map)['cachePath'], '/c/a.lfp');
    });

    test('floatPreviewRead maps pixels and the stored info', () async {
      reply = (_) => {
        'pixels': Float32List.fromList([2, 1, 0.5, 1]),
        'ms': 7,
        'fullWidth': 5464,
        'fullHeight': 8192,
        'shoulderKnee': 0.86,
        'highlightGain': 0.5,
      };
      const decoder = PlatformFloatDecoder(platform: _mac);
      final hit = await decoder.readPreview('/c/a.lfp', width: 1, height: 1);
      expect(hit!.pixels.rgba, [2, 1, 0.5, 1]);
      expect(hit.pixels.decodeMs, 7);
      expect((hit.info.width, hit.info.height), (5464, 8192));
      expect(hit.info.profile, HbdProfile.rawExtended);
      expect(calls.single.method, 'floatPreviewRead');
      expect(calls.single.arguments, {
        'cachePath': '/c/a.lfp',
        'width': 1,
        'height': 1,
      });
      // A miss, a short or incomplete answer, a native failure: no entry.
      reply = (_) => null;
      expect(await decoder.readPreview('/c/a.lfp', width: 1, height: 1), null);
      reply = (_) => {
        'pixels': Float32List(8),
        'fullWidth': 2,
        'fullHeight': 1,
      };
      expect(await decoder.readPreview('/c/a.lfp', width: 1, height: 1), null);
      reply = (_) => {'pixels': Float32List(4), 'fullWidth': 0};
      expect(await decoder.readPreview('/c/a.lfp', width: 1, height: 1), null);
      reply = (_) => throw PlatformException(code: 'x');
      expect(await decoder.readPreview('/c/a.lfp', width: 1, height: 1), null);
      calls.clear();
      expect(
        await const PlatformFloatDecoder(platform: _windows)
            .readPreview('/c/a.lfp', width: 1, height: 1),
        isNull,
      );
      expect(calls, isEmpty);
    });

    test('floatPreviewBuild returns the entry size', () async {
      reply = (_) => {'bytes': 17000000, 'ms': 640};
      const decoder = PlatformFloatDecoder(platform: _mac);
      expect(
        await decoder.buildPreview(
          '/x/a.cr3',
          cachePath: '/c/a.lfp',
          fullWidth: 1708,
          fullHeight: 2560,
        ),
        17000000,
      );
      expect(calls.single.method, 'floatPreviewBuild');
      expect(calls.single.arguments, {
        'input': '/x/a.cr3',
        'cachePath': '/c/a.lfp',
        'fullWidth': 1708,
        'fullHeight': 2560,
      });
      reply = (_) => throw PlatformException(code: 'float_failed');
      expect(
        await decoder.buildPreview(
          '/x/a.cr3',
          cachePath: '/c/a.lfp',
          fullWidth: 1,
          fullHeight: 1,
        ),
        isNull,
      );
      calls.clear();
      expect(
        await const PlatformFloatDecoder(platform: _windows).buildPreview(
          '/x/a.cr3',
          cachePath: '/c/a.lfp',
          fullWidth: 1,
          fullHeight: 1,
        ),
        isNull,
      );
      expect(calls, isEmpty);
    });

    test('floatRelease is sent and failures are swallowed', () async {
      reply = (_) => null;
      await const PlatformFloatDecoder(platform: _mac).release('/x/a.cr3');
      expect(calls.single.method, 'floatRelease');
      reply = (_) => throw PlatformException(code: 'x');
      await const PlatformFloatDecoder(platform: _mac).release('/x/a.cr3');
    });

    test('without the native handler there is no float decode', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      const decoder = PlatformFloatDecoder(platform: _mac);
      expect(await decoder.info('/x/a.cr3'), isNull);
      await decoder.release('/x/a.cr3');
      expect(await decoder.readPreview('/c', width: 1, height: 1), isNull);
      expect(
        await decoder.buildPreview(
          '/x/a.cr3',
          cachePath: '/c',
          fullWidth: 1,
          fullHeight: 1,
        ),
        isNull,
      );
      await expectLater(
        decoder.render(
          '/x/a.cr3',
          fullWidth: 1,
          fullHeight: 1,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
        throwsA(isA<FloatSourceException>()),
      );
    });
  });

  group('photo info', () {
    Map<String, String> file(CatalogEntry e, {bool float = false}) => {
      for (final (k, v) in photoInfo(e, floatEditing: float).first.rows) k: v,
    };

    test('RAW shows its declared depth, or just "RAW"', () {
      expect(file(_entry('dng', bitDepth: 14))['Bit depth'], '14-bit RAW');
      expect(file(_entry('cr3'))['Bit depth'], 'RAW');
      expect(file(_entry('threeFr', bitDepth: 16))['Bit depth'], '16-bit RAW');
    });

    test('other formats show what the file stores, never a guess', () {
      expect(file(_entry('png', bitDepth: 16))['Bit depth'], '16-bit');
      expect(file(_entry('heic', bitDepth: 10))['Bit depth'], '10-bit');
      expect(file(_entry('jpeg'))['Bit depth'], '8-bit');
      expect(file(_entry('webp'))['Bit depth'], '8-bit');
      // PNG / HEIC from a catalog that never recorded it: no row.
      expect(file(_entry('png')).containsKey('Bit depth'), isFalse);
      expect(file(_entry('heic')).containsKey('Bit depth'), isFalse);
    });

    test('Editing says which path the editor uses', () {
      expect(file(_entry('cr3'), float: true)['Editing'], '32-bit float');
      expect(file(_entry('cr3'))['Editing'], '8-bit');
      expect(file(_entry('jpeg'))['Editing'], '8-bit');
    });
  });
}
