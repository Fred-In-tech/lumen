import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('whiteBalanceGains', () {
    test('neutral temp/tint gives unit gains', () {
      final g = whiteBalanceGains(0, 0);
      expect(g.r, 1);
      expect(g.g, 1);
      expect(g.b, 1);
    });

    test('+100 temp doubles the R/B ratio (kappa_t = 1)', () {
      final g = whiteBalanceGains(100, 0);
      expect(g.r / g.b, closeTo(2, 1e-12));
      expect(g.g, 1);
      expect(g.r, greaterThan(1));
      expect(g.b, lessThan(1));
    });

    test('-100 temp halves the R/B ratio', () {
      final g = whiteBalanceGains(-100, 0);
      expect(g.r / g.b, closeTo(0.5, 1e-12));
    });

    test('+tint is magenta: green drops by 2^-0.5 at +100 (kappa_g = 0.5)', () {
      final g = whiteBalanceGains(0, 100);
      expect(g.g, closeTo(0.7071067811865476, 1e-12));
      expect(g.r, 1);
      expect(g.b, 1);
    });

    test('inputs are clamped to -100..100', () {
      final a = whiteBalanceGains(500, -500);
      final b = whiteBalanceGains(100, -100);
      expect(a.r, b.r);
      expect(a.g, b.g);
      expect(a.b, b.b);
    });

    test('neutralizing temp/tint round-trips a cast', () {
      // A warm cast with log2(R/B) = 0.4 is neutralized by temp = -40.
      final g = whiteBalanceGains(-40, 0);
      expect(g.r / g.b, closeTo(1 / 1.3195079107728942, 1e-9));
    });
  });
}
