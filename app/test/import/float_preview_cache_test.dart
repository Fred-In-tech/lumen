import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/import/float_preview_cache_io.dart';
import 'package:lumen/import/float_preview_cache_types.dart';
import 'package:lumen/platform/platform_info.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import '../support/fake_float_preview.dart';

/// The float preview cache folder (docs/HIGH_BIT_DEPTH.md, "Preview cache"):
/// names, the header the Dart side reads, LRU eviction under a size cap.

const _linux = PlatformInfo(
  isMacOS: false,
  isWindows: false,
  isLinux: true,
  isIOS: false,
  isAndroid: false,
);

void main() {
  group('names and header', () {
    test('file names carry the asset, the version and the size', () {
      expect(
        floatPreviewFileName('abc_1-2', 1708, 2560),
        'abc_1-2.v$kFloatPreviewCacheVersion.1708x2560.lfp',
      );
      expect(assetIdOfFloatPreview('abc_1-2.v1.1708x2560.lfp'), 'abc_1-2');
      // Ids that could leave the folder, empty sizes, other versions.
      expect(floatPreviewFileName('../x', 1, 1), isNull);
      expect(floatPreviewFileName('a/b', 1, 1), isNull);
      expect(floatPreviewFileName('a', 0, 1), isNull);
      expect(assetIdOfFloatPreview('a.v999.1x1.lfp'), isNull);
      expect(assetIdOfFloatPreview('.tmp-123'), isNull);
    });

    test('the header gives the full size and the develop profile', () {
      final info = parseFloatPreviewHeader(
        floatPreviewHeader(
          width: 1708,
          height: 2560,
          fullWidth: 5464,
          fullHeight: 8192,
        ),
      );
      expect((info!.width, info.height), (5464, 8192));
      expect(info.profile, HbdProfile.rawExtended);
      final flat = parseFloatPreviewHeader(
        floatPreviewHeader(width: 1, height: 1, knee: 0, gain: 0),
      );
      expect(flat!.profile, HbdProfile.none);
    });

    test('anything else is not a header', () {
      expect(parseFloatPreviewHeader(Uint8List(10)), isNull);
      expect(
        parseFloatPreviewHeader(
          floatPreviewHeader(width: 1, height: 1, magic: 7),
        ),
        isNull,
      );
      expect(
        parseFloatPreviewHeader(
          floatPreviewHeader(width: 1, height: 1, version: 99),
        ),
        isNull,
      );
      expect(
        parseFloatPreviewHeader(
          floatPreviewHeader(width: 1, height: 1, fullWidth: 0),
        ),
        isNull,
      );
      expect(
        parseFloatPreviewHeader(
          floatPreviewHeader(width: 1, height: 1, knee: double.nan),
        ),
        isNull,
      );
    });
  });

  group('FileFloatPreviewCache', () {
    late Directory root;
    late String dir;
    var now = DateTime.utc(2026, 10, 7, 12);

    setUp(() {
      root = Directory.systemTemp.createTempSync('lumen_fpc');
      dir = p.join(root.path, 'float_previews');
      now = DateTime.utc(2026, 10, 7, 12);
    });
    tearDown(() => root.deleteSync(recursive: true));

    FileFloatPreviewCache cache({int maxBytes = 1000}) => FileFloatPreviewCache(
      () async => dir,
      maxBytes: maxBytes,
      clock: () => now,
    );

    /// An entry of [bytes] bytes (header + padding), last used [age] ago.
    Future<String> put(
      FileFloatPreviewCache c,
      String id, {
      int bytes = 300,
      Duration age = Duration.zero,
    }) async {
      final path = (await c.pathFor(id, 4, 2))!;
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([
          ...floatPreviewHeader(width: 4, height: 2),
          ...List.filled(bytes - kFloatPreviewHeaderBytes, 0),
        ])
        ..setLastModifiedSync(now.subtract(age));
      return path;
    }

    test('paths live in the folder, which is created on first use', () async {
      final c = cache();
      final path = await c.pathFor('a', 4, 2);
      expect(p.dirname(path!), dir);
      expect(Directory(dir).existsSync(), isTrue);
      expect(await c.pathFor('../a', 4, 2), isNull);
      expect(await c.contains('a', 4, 2), isFalse);
      await put(c, 'a');
      expect(await c.contains('a', 4, 2), isTrue);
      expect(await c.contains('a', 4, 3), isFalse);
    });

    test('infoFor reads the header of any entry of the photo', () async {
      final c = cache();
      expect(await c.infoFor('a'), isNull);
      await put(c, 'a');
      final info = await c.infoFor('a');
      expect((info!.width, info.height), (600, 400));
      expect(await c.infoFor('b'), isNull);
      // A broken file is no answer.
      File((await c.pathFor('b', 4, 2))!).writeAsBytesSync([1, 2, 3]);
      expect(await c.infoFor('b'), isNull);
    });

    test('trim evicts least recently used entries down to the cap', () async {
      final c = cache();
      final old = await put(c, 'old', age: const Duration(days: 3));
      final mid = await put(c, 'mid', age: const Duration(days: 2));
      final kept = await put(c, 'kept', age: const Duration(days: 5));
      final fresh = await put(c, 'fresh');
      expect(await c.sizeInBytes(), 1200);
      // `kept` is the oldest but in use (open in the editor).
      final freed = await c.trim(keep: {kept});
      expect(freed, 300);
      expect(File(old).existsSync(), isFalse);
      expect(File(mid).existsSync(), isTrue);
      expect(File(kept).existsSync(), isTrue);
      expect(File(fresh).existsSync(), isTrue);
      expect(await c.sizeInBytes(), 900);
      // Under the cap: nothing to do.
      expect(await c.trim(), 0);
    });

    test('touch makes an entry recent again', () async {
      final c = cache(maxBytes: 600);
      final a = await put(c, 'a', age: const Duration(days: 9));
      final b = await put(c, 'b', age: const Duration(days: 1));
      final x = await put(c, 'x', age: const Duration(days: 2));
      await c.touch(a);
      await c.trim();
      expect(File(a).existsSync(), isTrue);
      expect(File(x).existsSync(), isFalse);
      expect(File(b).existsSync(), isTrue);
      await c.touch(p.join(dir, 'gone.lfp')); // no throw
    });

    test('trim removes stale temporary files and old versions', () async {
      final c = cache();
      await c.pathFor('a', 1, 1);
      final staleTmp = File(p.join(dir, '.tmp-old'))
        ..writeAsStringSync('x')
        ..setLastModifiedSync(now.subtract(const Duration(hours: 1)));
      final liveTmp = File(p.join(dir, '.tmp-new'))..writeAsStringSync('x');
      liveTmp.setLastModifiedSync(now);
      final oldVersion = File(p.join(dir, 'a.v0.4x2.lfp'))
        ..writeAsStringSync('x');
      await c.trim();
      expect(staleTmp.existsSync(), isFalse);
      expect(liveTmp.existsSync(), isTrue, reason: 'a write in progress');
      expect(oldVersion.existsSync(), isFalse);
    });

    test('remove deletes every entry of a photo', () async {
      final c = cache();
      final a = await put(c, 'a');
      final b = await put(c, 'b');
      await c.remove('a');
      expect(File(a).existsSync(), isFalse);
      expect(File(b).existsSync(), isTrue);
    });

    test('no caches directory: no cache, no throw', () async {
      final c = FileFloatPreviewCache(
        () async => throw const FileSystemException('no caches dir'),
      );
      expect(await c.pathFor('a', 1, 1), isNull);
      expect(await c.contains('a', 1, 1), isFalse);
      expect(await c.infoFor('a'), isNull);
      expect(await c.trim(), 0);
      expect(await c.sizeInBytes(), 0);
    });

    test('platforms without the float decoder get no cache', () async {
      final c = platformFloatPreviewCache(platform: _linux);
      expect(c, isA<NoFloatPreviewCache>());
      expect(await c.pathFor('a', 1, 1), isNull);
      expect(await c.infoFor('a'), isNull);
      expect(await c.contains('a', 1, 1), isFalse);
      expect(await c.trim(), 0);
      expect(await c.sizeInBytes(), 0);
      await c.touch('x');
      await c.remove('a');
    });
  });
}
