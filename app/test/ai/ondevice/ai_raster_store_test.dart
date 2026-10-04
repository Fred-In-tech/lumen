import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ondevice/ai_raster_store.dart';
import 'package:lumen/ai/ondevice/ai_raster_store_io.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

const _id = '0123456789abcdef0123456789abcdef';
const _ref = 'people.selfie_multiclass_256-1';

MaskRaster _random(int w, int h, [int seed = 1]) {
  final rnd = math.Random(seed);
  return MaskRaster(
    w,
    h,
    Uint8List.fromList([for (var i = 0; i < w * h; i++) rnd.nextInt(256)]),
  );
}

void main() {
  test('PNG codec round-trips coverage exactly', () {
    for (final (w, h) in [(1, 1), (7, 3), (64, 48), (301, 17)]) {
      final r = _random(w, h, w);
      final back = decodeMaskPng(encodeMaskPng(r))!;
      expect((back.width, back.height), (w, h));
      expect(back.data, r.data);
    }
    expect(decodeMaskPng(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('RGB PNGs decode from the first channel', () {
    final rgb = img.Image(width: 2, height: 1);
    rgb.setPixelRgb(0, 0, 200, 10, 10);
    rgb.setPixelRgb(1, 0, 30, 250, 250);
    final r = decodeMaskPng(img.encodePng(rgb))!;
    expect(r.data, [200, 30]);
  });

  test('mask refs that could escape the folder are rejected', () {
    for (final bad in ['../x', 'a/b', '', '..', r'a\b', '.hidden', 'a..b']) {
      expect(() => checkMaskRef(bad), throwsArgumentError, reason: bad);
    }
    expect(checkMaskRef(_ref), _ref);
  });

  group('FileAiRasterStore', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('rasters'));
    tearDown(() => tmp.delete(recursive: true));

    test(
      'writes assets/<id>/cache/masks/<ref>.png and reads it back',
      () async {
        final store = FileAiRasterStore(tmp.path);
        final r = _random(120, 80);
        expect(await store.exists(_id, _ref), isFalse);
        expect(await store.read(_id, _ref), isNull);

        await store.write(_id, _ref, r);

        final path = p.join(
          tmp.path,
          'assets',
          _id,
          'cache',
          'masks',
          '$_ref.png',
        );
        expect(store.pathFor(_id, _ref), path);
        expect(File(path).existsSync(), isTrue);
        expect(await store.exists(_id, _ref), isTrue);
        final back = (await FileAiRasterStore(tmp.path).read(_id, _ref))!;
        expect(back.data, r.data);
        expect(() => store.pathFor('../x', _ref), throwsArgumentError);
      },
    );
  });

  test('MemoryAiRasterStore round-trips through the codec', () async {
    final store = MemoryAiRasterStore();
    final r = _random(10, 6);
    await store.write(_id, _ref, r);
    expect(store.files.keys.single, '$_id/cache/masks/$_ref.png');
    expect((await store.read(_id, _ref))!.data, r.data);
  });
}
