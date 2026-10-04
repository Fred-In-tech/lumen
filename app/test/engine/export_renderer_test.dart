import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/image_encoder.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';

/// PLAN.md P2.11: tiled export equals a single-pass render; encoder output.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = DevelopSettings.defaults.withValues({
    P.exposure: 0.3,
    P.contrast: 25,
    P.shadows: 40,
    P.clarity: 30,
    P.texture: 20,
    P.sharpenAmount: 80,
    P.grainAmount: 30,
    P.vignetteAmount: -40,
  });

  test(
    '3000x2000 tiled render equals the single-pass render (<= 1/255)',
    () async {
      final shaders = await ShaderLibrary.load();
      final scene = TestScenes.portrait(3000, 2000);
      final source = await imageFromBuffer(scene);
      final aux = await AuxTextures.fromMaps(
        AuxMaps.compute(AuxMaps.proxy(scene)),
      );
      final renderer = ExportRenderer(shaders);
      final progress = <double>[];
      final tiled = await renderer.render(
        source: source,
        aux: aux,
        settings: settings,
        assetId: 'a1',
        tileSize: 1024,
        onProgress: progress.add,
      );
      final single = await renderer.render(
        source: source,
        aux: aux,
        settings: settings,
        assetId: 'a1',
        tileSize: 4096,
      );
      expect([tiled.width, tiled.height], [3000, 2000]);
      final d = diffStats(
        RgbaBuffer(3000, 2000, tiled.rgba),
        RgbaBuffer(3000, 2000, single.rgba),
      );
      expect(d.max, lessThanOrEqualTo(1));
      expect(progress, hasLength(6));
      expect(progress.last, 1);
      aux.dispose();
      EngineImages.dispose(source);
      expect(EngineImages.live, 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('long-edge resize, crop and rotation set the export size', () {
    final g = Geometry.none.copyWith(
      rotate90: 1,
      crop: const CropRect(0, 0, 0.5, 1),
    );
    expect(ExportRenderer.exportSize(4000, 3000, g), (
      width: 1500,
      height: 4000,
    ));
    expect(ExportRenderer.exportSize(4000, 3000, g, longEdge: 2000), (
      width: 750,
      height: 2000,
    ));
    expect(ExportRenderer.exportSize(400, 300, Geometry.none, longEdge: 2000), (
      width: 400,
      height: 300,
    ));
  });

  test('cancellation stops between tiles and leaks nothing', () async {
    final shaders = await ShaderLibrary.load();
    final scene = TestScenes.rampAndHues(600, 400);
    final source = await imageFromBuffer(scene);
    final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
    final token = CancelToken();
    var tiles = 0;
    await expectLater(
      ExportRenderer(shaders).render(
        source: source,
        aux: aux,
        settings: settings.withValue(P.noiseLuminance, 30),
        tileSize: 128,
        cancel: token,
        onProgress: (_) {
          if (++tiles == 3) token.cancel();
        },
      ),
      throwsA(isA<ExportCancelled>()),
    );
    expect(tiles, 3);
    aux.dispose();
    EngineImages.dispose(source);
    expect(EngineImages.live, 0);
  });

  test('decodeOriginal decodes and caps the long edge', () async {
    final jpg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 400, height: 200), quality: 90),
    );
    final full = await ExportRenderer.decodeOriginal(jpg);
    expect([full.width, full.height], [400, 200]);
    final capped = await ExportRenderer.decodeOriginal(jpg, maxLongEdge: 100);
    expect([capped.width, capped.height], [100, 50]);
    EngineImages.dispose(full);
    EngineImages.dispose(capped);
  });

  group('image encoder', () {
    final pixels = RgbaBuffer.filled(120, 80, 200, 100, 50).data;

    test('JPEG and PNG decode back with the expected size', () async {
      for (final format in ExportFormat.values) {
        final bytes = await encodeImage(
          EncodeRequest(
            width: 120,
            height: 80,
            rgba: pixels,
            format: format,
            quality: 90,
          ),
        );
        final back = img.decodeImage(bytes)!;
        expect([back.width, back.height], [120, 80], reason: format.name);
        final p = back.getPixel(60, 40);
        expect(p.r.toInt(), closeTo(200, 3));
        expect(p.b.toInt(), closeTo(50, 3));
      }
    });

    test('lower JPEG quality gives a smaller file', () async {
      final scene = TestScenes.texture(200, 150).data;
      Future<int> size(int q) async => (await encodeImage(
        EncodeRequest(width: 200, height: 150, rgba: scene, quality: q),
      )).length;
      expect(await size(30), lessThan(await size(95)));
    });

    test(
      'EXIF is copied without GPS and serial numbers, orientation reset',
      () async {
        final original = img.Image(width: 8, height: 8);
        original.exif.imageIfd['Make'] = 'TestCam';
        original.exif.imageIfd['Orientation'] = 6;
        original.exif.exifIfd[0xA431] = 'SERIAL123';
        original.exif.gpsIfd[0x0001] = img.IfdValueAscii('N'); // GPSLatitudeRef
        final src = Uint8List.fromList(img.encodeJpg(original));
        expect(img.decodeJpgExif(src)!.gpsIfd.isEmpty, isFalse);

        final out = await encodeImage(
          EncodeRequest(width: 120, height: 80, rgba: pixels, exifSource: src),
        );
        final exif = img.decodeJpgExif(out)!;
        expect(exif.imageIfd['Make']?.toString(), contains('TestCam'));
        expect(exif.gpsIfd.isEmpty, isTrue);
        expect(exif.exifIfd[0xA431], isNull);
        expect(exif.imageIfd.orientation, 1);
      },
    );

    test('rejects a mismatched buffer', () {
      expect(
        () => encodeImageSync(
          EncodeRequest(width: 10, height: 10, rgba: Uint8List(4)),
        ),
        throwsArgumentError,
      );
    });
  });
}
