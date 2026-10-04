import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('SsdAnchorConfig', () {
    test('short-range has 896 = 16x16x2 + 8x8x6 anchors', () {
      const c = SsdAnchorConfig.shortRange;
      final anchors = c.generate();
      expect(c.anchorCount, 896);
      expect(anchors, hasLength(896));
      expect(16 * 16 * 2 + 8 * 8 * 6, 896);
    });

    test('short-range anchor order: stride 8 cells then stride 16 cells', () {
      final a = SsdAnchorConfig.shortRange.generate();
      // Two anchors per stride-8 cell, same centre, unit size.
      expect(a[0].centerX, closeTo(0.5 / 16, 1e-12));
      expect(a[0].centerY, closeTo(0.5 / 16, 1e-12));
      expect(a[1].centerX, a[0].centerX);
      expect(a[0].width, 1);
      expect(a[0].height, 1);
      expect(a[2].centerX, closeTo(1.5 / 16, 1e-12));
      // First stride-16 anchor, then six per cell.
      expect(a[512].centerX, closeTo(0.5 / 8, 1e-12));
      expect(a[512].centerY, closeTo(0.5 / 8, 1e-12));
      expect(a[517].centerX, a[512].centerX);
      expect(a[518].centerX, closeTo(1.5 / 8, 1e-12));
      expect(a.last.centerX, closeTo(7.5 / 8, 1e-12));
      expect(a.last.centerY, closeTo(7.5 / 8, 1e-12));
    });

    test('full-range: one anchor per stride-4 cell', () {
      expect(SsdAnchorConfig.fullRange.anchorCount, 48 * 48);
      final at128 = SsdAnchorConfig.fullRange.withInputSize(128, 128);
      expect(at128.anchorCount, 32 * 32);
      expect(at128.generate(), hasLength(1024));
    });

    test('resolve picks the layout from tensor shapes', () {
      expect(
        SsdAnchorConfig.resolve(
          inputWidth: 128,
          inputHeight: 128,
          anchorCount: 896,
        ).name,
        'short_range',
      );
      final full = SsdAnchorConfig.resolve(
        inputWidth: 192,
        inputHeight: 192,
        anchorCount: 2304,
      );
      expect(full.name, 'full_range');
      expect(full.inputWidth, 192);
      expect(
        SsdAnchorConfig.resolve(
          inputWidth: 128,
          inputHeight: 128,
          anchorCount: 1024,
        ).name,
        'full_range',
      );
    });

    test('resolve throws a typed error on an unknown layout', () {
      expect(
        () => SsdAnchorConfig.resolve(
          inputWidth: 128,
          inputHeight: 128,
          anchorCount: 1000,
        ),
        throwsA(isA<AnchorLayoutException>()),
      );
    });

    test('non-fixed anchors carry scale-derived sizes', () {
      const c = SsdAnchorConfig(
        name: 'sized',
        inputWidth: 64,
        inputHeight: 64,
        strides: [16, 32],
        fixedAnchorSize: false,
      );
      final a = c.generate();
      expect(a, hasLength(c.anchorCount));
      expect(c.anchorCount, 4 * 4 * 2 + 2 * 2 * 2);
      // Layer 0: min scale, aspect 1 → square anchor of size minScale.
      expect(a[0].width, closeTo(c.minScale, 1e-12));
      expect(a[0].height, closeTo(c.minScale, 1e-12));
    });
  });
}
