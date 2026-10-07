import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/export/export_targets_io.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

/// A camera-like JPEG: Make/Model, exposure, GPS and a body serial.
Uint8List _cameraJpeg({int w = 64, int h = 48}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, x * 4, y * 5, 128);
    }
  }
  im.exif.imageIfd['Make'] = 'Canon';
  im.exif.imageIfd['Model'] = 'EOS R5';
  im.exif.exifIfd[0x8827] = img.IfdValueShort(400);
  im.exif.exifIfd[0xA431] = img.IfdValueAscii('SERIAL123');
  im.exif.gpsIfd['GPSLatitudeRef'] = 'N';
  im.exif.gpsIfd['GPSLatitude'] = [51.0, 30.0, 0.0];
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// A float export stand-in: a 16-bit horizontal ramp with 1000+ levels.
FloatExportRenderer _rampFloat({int w = 1200, int h = 4}) => (r) async {
  if (!r.sixteenBit) return null;
  final rgb = Uint16List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = (65535 * x / (w - 1)).round();
      final o = (y * w + x) * 3;
      rgb[o] = v;
      rgb[o + 1] = v;
      rgb[o + 2] = 65535 - v;
    }
  }
  return Raster16(w, h, rgb, fromFloat: true);
};

Future<(MemoryCatalogRepository, String)> _photo(Uint8List bytes) async {
  final repo = MemoryCatalogRepository();
  final r = await ImportService(repo)
      .importOne(ImportFile(name: 'IMG_0001.jpg', bytes: bytes));
  return (repo, (r as Imported).entry.assetId);
}

int _levels(img.Image im) =>
    {for (var x = 0; x < im.width; x++) im.getPixel(x, 1).r.toInt()}.length;

void main() {
  test('TIFF 16-bit from a float source keeps >256 levels, sRGB ICC, '
      'camera EXIF without GPS or serial', () async {
    final (repo, id) = await _photo(_cameraJpeg());
    final f = await ExportService(
      repo,
      floatExport: _rampFloat(),
    ).exportOne(id, const ExportOptions(format: ExportFormat.tiff16));
    expect(f.fileName, 'IMG_0001_edit.tif');
    expect(f.sixteenBitDetail, isTrue);
    expect(f.chunks, hasLength(2), reason: 'header + the frame, no copy');
    expect(f.length, f.bytes.length);
    final tiff = img.decodeTiff(f.bytes)!;
    expect(tiff.format, img.Format.uint16);
    expect((tiff.width, tiff.height), (1200, 4));
    expect(_levels(tiff), 1200);
    expect(tiff.getPixel(1199, 0).r, 65535);
    expect(tiff.getPixel(0, 0).b, 65535);

    final tags = await readExifFromBytes(f.bytes);
    expect(tags['Image Make']?.printable, 'Canon');
    expect(tags['Image Model']?.printable, 'EOS R5');
    expect(tags['EXIF ISOSpeedRatings']?.printable, '400');
    expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty);
    expect(tags.keys.where((k) => k.contains('Serial')), isEmpty);
    expect(tags['Image BitsPerSample']?.printable, '[16, 16, 16]');
    final icc = tags['Image InterColorProfile'] ?? tags['Image Tag 0x8773'];
    expect(icc, isNotNull);

    final dir = await Directory.systemTemp.createTemp('lumen_tiff');
    addTearDown(() => dir.delete(recursive: true));
    final path = (await writeExports(dir.path, [f])).single;
    expect(File(path).readAsBytesSync(), f.bytes);
  });

  test('PNG 16-bit: levels, iCCP and an eXIf chunk without GPS', () async {
    final (repo, id) = await _photo(_cameraJpeg());
    final f = await ExportService(
      repo,
      floatExport: _rampFloat(),
    ).exportOne(id, const ExportOptions(format: ExportFormat.png16));
    expect(f.fileName, 'IMG_0001_edit.png');
    final png = img.decodePng(f.bytes)!;
    expect(png.format, img.Format.uint16);
    expect(_levels(png), 1200);
    expect(png.iccProfile, isNotNull);
    final b = f.bytes;
    final s = String.fromCharCodes(b);
    expect(s.indexOf('eXIf'), lessThan(s.indexOf('IDAT')));
    expect(s.contains('Canon'), isTrue);
    expect(s.contains('SERIAL123'), isFalse);
  });

  test('8-bit photo to 16-bit: widened, marked as no extra detail', () async {
    final (repo, id) = await _photo(_cameraJpeg());
    final f = await ExportService(repo)
        .exportOne(id, const ExportOptions(format: ExportFormat.tiff16));
    expect(f.sixteenBitDetail, isFalse);
    final tiff = img.decodeTiff(f.bytes)!;
    expect(tiff.format, img.Format.uint16);
    expect((tiff.width, tiff.height), (64, 48));
    for (var x = 0; x < 64; x += 7) {
      expect(tiff.getPixel(x, 3).r.toInt() % 257, 0);
    }
  });

  test('size limit, sharpen, watermark and naming from a preset', () async {
    final (repo, id) = await _photo(_cameraJpeg(w: 400, h: 300));
    var drawn = 0;
    final service = ExportService(
      repo,
      clock: () => DateTime(2026, 5, 4),
      watermarkRasterizer: (text, height, maxWidth) async {
        drawn++;
        expect(text, '© FVM');
        expect(height, closeTo(0.1 * 150, 0.01));
        return WatermarkMask(4, 2, Uint8List.fromList(List.filled(8, 255)));
      },
    );
    const preset = ExportPreset(
      id: 'p',
      name: 'Proof',
      format: ExportFileFormat.png,
      size: ExportSizeLimit.box(200, 200),
      sharpen: OutputSharpen.screen,
      naming: '{preset}-{seq}-{date}-{name}',
      watermark: Watermark(
        text: '© FVM',
        position: WatermarkPosition.topLeft,
        opacity: 1,
        size: 0.1,
      ),
    );
    final f = await service.exportOne(
      id,
      ExportOptions.fromPreset(preset),
      seq: 3,
      total: 12,
    );
    expect(drawn, 1);
    expect((f.width, f.height), (200, 150));
    expect(f.fileName, 'Proof-03-2026-05-04-IMG_0001.png');
    final png = img.decodePng(f.bytes)!;
    final margin = (150 * 0.03).round();
    expect(png.getPixel(margin, margin).r, 255, reason: 'white watermark');
    expect(png.getPixel(margin, margin).b, 255);
  });

  test('megapixel limit and a 16-bit raster refused as JPEG', () async {
    final (repo, id) = await _photo(_cameraJpeg(w: 400, h: 300));
    final f = await ExportService(
      repo,
    ).exportOne(id, const ExportOptions(size: ExportSizeLimit.megapixels(0)));
    expect((f.width, f.height), (400, 300), reason: 'junk limit is none');
    expect(
      () => encodeRaster(
        Raster16(1, 1, Uint16List(3), fromFloat: true),
        format: ExportFormat.jpeg,
      ),
      throwsArgumentError,
    );
    expect(
      () => Raster16(2, 2, Uint16List(3), fromFloat: true),
      throwsArgumentError,
    );
    expect(
      () => encodeExport(RgbaBuffer(1, 1), format: ExportFormat.tiff16),
      throwsArgumentError,
    );
    expect(crc32(Uint8List.fromList('IEND'.codeUnits)), 0xAE426082);
    expect(exportFileName('a.HEIC', ExportFormat.tiff16), 'a_edit.tif');
    final renamed = f.renamed('x.jpg');
    expect(renamed.fileName, 'x.jpg');
    expect(renamed.bytes, f.bytes);
  });
}
