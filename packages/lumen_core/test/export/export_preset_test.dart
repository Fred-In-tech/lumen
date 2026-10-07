import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('ExportSizeLimit', () {
    test('none keeps the size', () {
      expect(const ExportSizeLimit.none().fit(6000, 4000), (6000, 4000));
      expect(const ExportSizeLimit.none().longEdgeFor(6000, 4000), isNull);
    });

    test('long edge never upscales', () {
      const l = ExportSizeLimit.longEdge(2048);
      expect(l.fit(6000, 4000), (2048, 1365));
      expect(l.fit(4000, 6000), (1365, 2048));
      expect(l.fit(1000, 800), (1000, 800));
      expect(l.longEdgeFor(6000, 4000), 2048);
      expect(l.longEdgeFor(1000, 800), isNull);
    });

    test('megapixels keeps the aspect under the pixel count', () {
      const l = ExportSizeLimit.megapixels(12);
      final (w, h) = l.fit(8192, 5464);
      expect(w * h, lessThanOrEqualTo(12000000));
      expect(w * h, greaterThan(11900000));
      expect((w / h - 8192 / 5464).abs(), lessThan(0.002));
      expect(l.fit(3000, 2000), (3000, 2000));
    });

    test('box is 4:5 aware (Instagram)', () {
      const l = ExportSizeLimit.box(1080, 1350);
      expect(l.fit(4000, 5000), (1080, 1350)); // 4:5 portrait
      expect(l.fit(4000, 6000), (900, 1350)); // 2:3 portrait
      expect(l.fit(6000, 4000), (1080, 720)); // landscape
      expect(l.fit(800, 600), (800, 600));
      expect(l.longEdgeFor(4000, 6000), 1350);
      expect(l.longEdgeFor(6000, 4000), 1080);
    });

    test('json round trip and labels', () {
      for (final l in const [
        ExportSizeLimit.none(),
        ExportSizeLimit.longEdge(2048),
        ExportSizeLimit.megapixels(24),
        ExportSizeLimit.box(1080, 1350),
      ]) {
        expect(ExportSizeLimit.fromJson(l.toJson()), l);
        expect(l.label, isNotEmpty);
      }
      expect(ExportSizeLimit.fromJson('junk'), const ExportSizeLimit.none());
      expect(
        ExportSizeLimit.fromJson({'kind': 'longEdge', 'value': -5}),
        const ExportSizeLimit.none(),
      );
      expect(
        const ExportSizeLimit.longEdge(10).hashCode,
        const ExportSizeLimit.longEdge(10).hashCode,
      );
    });
  });

  group('ExportPreset', () {
    test('built-ins are the four promised ones', () {
      final names = [for (final p in kBuiltinExportPresets) p.name];
      expect(names, [
        'Web (2048 px JPEG 85)',
        'Full size JPEG',
        'Print TIFF 16-bit full size',
        'Instagram 1080 px (4:5 aware, long edge 1350)',
      ]);
      expect(kBuiltinExportPresets.every((p) => p.builtin), isTrue);
      final web = kBuiltinExportPresets.first;
      expect(web.format, ExportFileFormat.jpeg);
      expect(web.quality, 85);
      expect(web.size, const ExportSizeLimit.longEdge(2048));
      final print = kBuiltinExportPresets[2];
      expect(print.format, ExportFileFormat.tiff16);
      expect(print.sharpen, OutputSharpen.printStandard);
      expect(print.size, const ExportSizeLimit.none());
    });

    test('json round trip with every field', () {
      const p = ExportPreset(
        id: 'u1',
        name: 'Client proofs',
        format: ExportFileFormat.png16,
        quality: 77,
        size: ExportSizeLimit.megapixels(8),
        sharpen: OutputSharpen.screen,
        naming: '{date}_{name}_{seq}',
        folder: '/Users/x/Proofs',
        keepMetadata: false,
        watermark: Watermark(
          text: '© Freddy',
          position: WatermarkPosition.topLeft,
          opacity: 0.4,
          size: 0.05,
        ),
      );
      final back = ExportPreset.fromJson(p.toJson());
      expect(back, p);
      expect(back.builtin, isFalse);
      expect(back.toJson(), p.toJson());
    });

    test('fromJson tolerates junk and clamps', () {
      final p = ExportPreset.fromJson({
        'id': 'x',
        'name': '',
        'format': 'gif',
        'quality': 500,
        'sharpen': 'max',
        'watermark': {'text': '', 'opacity': 9, 'size': -1},
      });
      expect(p.name, 'Untitled');
      expect(p.format, ExportFileFormat.jpeg);
      expect(p.quality, 100);
      expect(p.sharpen, OutputSharpen.none);
      expect(p.watermark, isNull);
      expect(p.naming, kDefaultNaming);
      final w = Watermark.fromJson({'text': 'a', 'opacity': 9, 'size': -1});
      expect(w!.opacity, 1);
      expect(w.size, kWatermarkMinSize);
      expect(Watermark.fromJson(42), isNull);
    });

    test('copyWith changes only what is given', () {
      final p = kBuiltinExportPresets.first.copyWith(
        id: 'mine',
        name: 'Mine',
        builtin: false,
        quality: 70,
        clearFolder: true,
        clearWatermark: true,
      );
      expect(p.id, 'mine');
      expect(p.quality, 70);
      expect(p.format, ExportFileFormat.jpeg);
      expect(p.builtin, isFalse);
      final q = p.copyWith(
        format: ExportFileFormat.tiff16,
        size: const ExportSizeLimit.none(),
        sharpen: OutputSharpen.printLow,
        naming: '{name}',
        folder: '/tmp',
        keepMetadata: false,
        watermark: const Watermark(text: 'x'),
      );
      expect(q.folder, '/tmp');
      expect(q.watermark!.text, 'x');
      expect(q.copyWith(clearFolder: true).folder, isNull);
      expect(p == q, isFalse);
      expect(p.hashCode == p.copyWith().hashCode, isTrue);
    });

    test('format facts', () {
      expect(ExportFileFormat.tiff16.extension, 'tif');
      expect(ExportFileFormat.png16.extension, 'png');
      expect(ExportFileFormat.png.extension, 'png');
      expect(ExportFileFormat.jpeg.extension, 'jpg');
      expect(ExportFileFormat.tiff16.sixteenBit, isTrue);
      expect(ExportFileFormat.jpeg.sixteenBit, isFalse);
      expect(ExportFileFormat.jpeg.hasQuality, isTrue);
      expect(ExportFileFormat.png16.hasQuality, isFalse);
      for (final f in ExportFileFormat.values) {
        expect(f.label, isNotEmpty);
        expect(ExportFileFormat.byName(f.name), f);
      }
      expect(ExportFileFormat.byName('nope'), ExportFileFormat.jpeg);
      for (final s in OutputSharpen.values) {
        expect(s.label, isNotEmpty);
      }
    });
  });
}
