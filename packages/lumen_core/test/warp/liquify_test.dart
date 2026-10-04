import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

WarpField _run(List<LiquifyStroke> strokes, {int w = 400, int h = 300}) =>
    buildWarpField(
      WarpRequest(sourceWidth: w, sourceHeight: h, liquify: strokes),
    );

const _pushRight = LiquifyStroke(
  tool: LiquifyTool.push,
  points: [(0.4, 0.5), (0.5, 0.5)],
  radius: 0.08,
  strength: 1,
);

void main() {
  test('push moves content along the stroke (backward map points back)', () {
    final f = _run([_pushRight]);
    final (du, dv) = f.sample(0.5, 0.5);
    // Content from the left now shows at the stroke end: src is left of it.
    expect(du, lessThan(-0.01));
    expect(dv.abs(), lessThan(0.002));
    expect(f.sample(0.05, 0.05), (0.0, 0.0));
    // Full-strength push compresses ahead of the brush but never folds.
    expect(f.minJacobian(), greaterThan(0.05));
  });

  test('reconstruct brushes back to about identity', () {
    final pushed = _run([_pushRight]);
    final restored = _run([
      _pushRight,
      const LiquifyStroke(
        tool: LiquifyTool.reconstruct,
        points: [
          (0.35, 0.5),
          (0.45, 0.5),
          (0.55, 0.5),
          (0.45, 0.5),
          (0.35, 0.5),
        ],
        radius: 0.2,
        strength: 1,
      ),
    ]);
    expect(pushed.maxDisplacement, greaterThan(0.01));
    expect(restored.maxDisplacement, lessThan(pushed.maxDisplacement * 0.05));
  });

  test('bloat magnifies, pucker shrinks (radial sign)', () {
    const c = (0.5, 0.5);
    final bloat = _run([
      const LiquifyStroke(
        tool: LiquifyTool.bloat,
        points: [c],
        radius: 0.1,
        strength: 1,
      ),
    ]);
    final pucker = _run([
      const LiquifyStroke(
        tool: LiquifyTool.pucker,
        points: [c],
        radius: 0.1,
        strength: 1,
      ),
    ]);
    // At a point right of the centre: bloat samples closer to it (-u).
    expect(bloat.sample(0.53, 0.5).$1, lessThan(0));
    expect(pucker.sample(0.53, 0.5).$1, greaterThan(0));
    expect(bloat.minJacobian(), greaterThan(0.2));
    expect(pucker.minJacobian(), greaterThan(0.2));
  });

  test('strokes replay deterministically and extend incrementally', () {
    final a = _run([_pushRight]);
    final b = _run([_pushRight]);
    expect(a.packRgba(), b.packRgba());
    // Incremental: base field + one more stroke == full replay.
    final base = _run([_pushRight]);
    const more = LiquifyStroke(
      tool: LiquifyTool.bloat,
      points: [(0.3, 0.3)],
      radius: 0.05,
      strength: 0.6,
    );
    final inc = applyLiquifyStrokes(
      base,
      const [more],
      sourceWidth: 400,
      sourceHeight: 300,
    );
    final full = _run([_pushRight, more]);
    expect(inc.packRgba(), full.packRgba());
  });

  test('the field never samples outside the image', () {
    final f = _run([
      const LiquifyStroke(
        tool: LiquifyTool.push,
        points: [(0.02, 0.5), (0.0, 0.5)],
        radius: 0.1,
        strength: 1,
      ),
    ]);
    for (var i = 0; i < f.width; i += 7) {
      for (var j = 0; j < f.height; j += 7) {
        final u = (i + 0.5) / f.width, v = (j + 0.5) / f.height;
        final (du, dv) = f.sample(u, v);
        expect(u + du, inInclusiveRange(-1e-6, 1 + 1e-6));
        expect(v + dv, inInclusiveRange(-1e-6, 1 + 1e-6));
      }
    }
  });

  test('buildWarpWithPrefix: full = replay, prefix = all but the last', () {
    const more = LiquifyStroke(
      tool: LiquifyTool.pucker,
      points: [(0.6, 0.6)],
      radius: 0.06,
      strength: 0.7,
    );
    const r = WarpRequest(
      sourceWidth: 400,
      sourceHeight: 300,
      liquify: [_pushRight, more],
    );
    final b = buildWarpWithPrefix(r);
    expect(b.full.packRgba(), buildWarpField(r).packRgba());
    expect(b.prefix.packRgba(), _run([_pushRight]).packRgba());
  });

  test('sourceUvOf maps output uv through the geometry', () {
    final s = DevelopSettings.defaults.copyWith(
      geometry: Geometry.none.copyWith(rotate90: 1),
    );
    final (u, v) = sourceUvOf(s, 400, 300, 0, 0);
    expect(u, closeTo(0, 1e-9));
    expect(v, closeTo(1, 1e-9));
    expect(sourceUvOf(DevelopSettings.defaults, 400, 300, 0.3, 0.6), (
      0.3,
      0.6,
    ));
  });

  test('LiquifyLive: growing a stroke point by point equals one shot', () {
    for (final tool in LiquifyTool.values) {
      final pts = [
        for (var i = 0; i < 12; i++) (0.3 + 0.03 * i, 0.4 + 0.01 * i),
      ];
      final base = _run([_pushRight]);
      LiquifyStroke at(int n) => LiquifyStroke(
        tool: tool,
        points: pts.sublist(0, n),
        radius: 0.07,
        strength: 0.7,
      );
      final live = LiquifyLive(base, at(1));
      for (var n = 2; n <= pts.length; n++) {
        expect(live.canExtend(at(n)), isTrue);
        live.extend(at(n));
      }
      final oneShot = LiquifyLive(base, at(pts.length)).snapshot();
      expect(live.snapshot().packRgba(), oneShot.packRgba(), reason: '$tool');
      expect(live.canExtend(_pushRight), isFalse);
    }
  });
}
