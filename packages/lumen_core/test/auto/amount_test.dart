import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  final pre = DevelopSettings.defaults.withValues({
    P.exposure: 0.2,
    P.clarity: 10,
  });
  final ai = applyOps(pre, [
    const DeltaOp(P.exposure, 2),
    const DeltaOp(P.shadows, 40),
    const DeltaOp(P.vignetteAmount, -60),
    ...StyleAtom.bwClassic.ops(1),
    ...StyleAtom.filmFaded.ops(1),
  ]).settings;

  group('applyAiAmount', () {
    test('0 % returns the pre-AI state exactly', () {
      expect(applyAiAmount(pre: pre, ai: ai, percent: 0), pre);
    });

    test('100 % returns the AI result exactly', () {
      expect(applyAiAmount(pre: pre, ai: ai, percent: 100), ai);
    });

    test('50 % is halfway for every AI-changed param', () {
      final half = applyAiAmount(pre: pre, ai: ai, percent: 50);
      expect(half.value(P.exposure), closeTo(1.2, 1e-9));
      expect(half.value(P.shadows), closeTo(20, 1e-9));
      expect(half.value(P.clarity), 10);
      expect(half.treatment, Treatment.bw);
      expect(half.curves.master.evaluate(0), closeTo(10, 1e-9));
    });

    test('below 50 % keeps the pre-AI treatment', () {
      final low = applyAiAmount(pre: pre, ai: ai, percent: 25);
      expect(low.treatment, Treatment.color);
      expect(low.value(P.shadows), closeTo(10, 1e-9));
    });

    test('150 % extrapolates and clamps to the registry range', () {
      final over = applyAiAmount(pre: pre, ai: ai, percent: 150);
      expect(over.value(P.exposure), closeTo(3.2, 1e-9));
      expect(over.value(P.shadows), closeTo(60, 1e-9));
      expect(over.value(P.vignetteAmount), -100);
      final wild = applyAiAmount(
        pre: DevelopSettings.defaults,
        ai: DevelopSettings.defaults.withValue(P.exposure, 4),
        percent: 150,
      );
      expect(wild.value(P.exposure), 5);
    });

    test('percent outside 0..150 is clamped', () {
      expect(applyAiAmount(pre: pre, ai: ai, percent: -20), pre);
      expect(
        applyAiAmount(pre: pre, ai: ai, percent: 400),
        applyAiAmount(pre: pre, ai: ai, percent: 150),
      );
    });
  });
}
