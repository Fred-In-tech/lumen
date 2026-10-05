import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/info/photo_info.dart';
import 'package:lumen/features/info/photo_info_dialog.dart';
import 'package:lumen_core/lumen_core.dart';

CatalogEntry _entry({ExifSummary exif = const ExifSummary()}) => CatalogEntry(
  assetId: 'a',
  fileName: '541A4390.cr3',
  originalPath: 'originals/a.cr3',
  format: 'cr3',
  width: 5464,
  height: 8192,
  bytes: 51 * (1 << 20) + 300000,
  importedAt: DateTime(2026, 10, 4, 9, 5),
  exif: exif,
);

void main() {
  test('lists file, camera and exposure facts with units', () {
    final info = photoInfo(
      _entry(
        exif: ExifSummary(
          camera: 'Canon EOS R5',
          lens: 'RF50mm F1.2 L USM',
          iso: 250,
          shutter: '1/125',
          aperture: 2,
          focalMm: 50,
          capturedAt: DateTime(2026, 9, 17, 10, 51, 29),
          flash: false,
          exposureBias: -0.333,
          program: 'Manual',
          metering: 'Pattern',
          whiteBalance: 'Auto',
          colorSpace: 'sRGB',
        ),
      ),
    );
    expect(info.map((s) => s.title), ['File', 'Camera', 'Exposure']);
    final rows = {
      for (final s in info)
        for (final (k, v) in s.rows) k: v,
    };
    expect(rows['Type'], 'Canon RAW (CR3)');
    expect(rows['Size'], '5464 × 8192  (44.8 MP)');
    expect(rows['File size'], '51.3 MB');
    expect(rows['Imported'], '2026-10-04 09:05');
    expect(rows['Taken'], '2026-09-17 10:51');
    expect(rows['Shutter'], '1/125 s');
    expect(rows['Aperture'], 'f/2');
    expect(rows['ISO'], '250');
    expect(rows['Focal length'], '50 mm');
    expect(rows['Exposure comp.'], '−0.33 EV');
    expect(rows['Flash'], 'Did not fire');
    expect(rows['White balance'], 'Auto');
  });

  test('a file without camera data shows only the File section', () {
    final info = photoInfo(_entry());
    expect(info.single.title, 'File');
  });

  test('labels sizes and unknown formats', () {
    expect(fileSizeLabel(830 * 1024), '830 KB');
    expect(fileSizeLabel(512), '512 bytes');
    expect(formatLabel('threeFr'), 'Hasselblad RAW (3FR)');
    expect(formatLabel('xyz'), 'XYZ');
  });

  test('the new EXIF fields survive JSON', () {
    const e = ExifSummary(
      exposureBias: 0.67,
      program: 'Aperture priority',
      metering: 'Spot',
      whiteBalance: 'Manual',
      colorSpace: 'sRGB',
      software: 'Firmware 1.8.1',
    );
    final back = ExifSummary.fromJson(e.toJson());
    expect(back.exposureBias, 0.67);
    expect(back.program, 'Aperture priority');
    expect(back.metering, 'Spot');
    expect(back.whiteBalance, 'Manual');
    expect(back.colorSpace, 'sRGB');
    expect(back.software, 'Firmware 1.8.1');
  });

  testWidgets('the dialog shows the rows and closes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLumenTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPhotoInfo(
                context,
                _entry(exif: const ExifSummary(camera: 'Canon EOS R5')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Photo info'), findsOneWidget);
    expect(find.text('Canon RAW (CR3)'), findsOneWidget);
    expect(find.text('Canon EOS R5'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Photo info'), findsNothing);
  });
}
