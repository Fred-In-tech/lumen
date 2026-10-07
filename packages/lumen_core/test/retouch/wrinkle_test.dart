import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;
const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140);

const _zoneIds = {
  SynthZone.forehead: PortraitIds.wrinkleForehead,
  SynthZone.frown: PortraitIds.wrinkleFrown,
  SynthZone.crowsFeet: PortraitIds.wrinkleCrowsFeet,
  SynthZone.smile: PortraitIds.wrinkleSmile,
  SynthZone.marionette: PortraitIds.wrinkleMarionette,
};

/// Valley depth of [w] in [l]: mean L of the line's sides (± 3σ + 0.02
/// IOD) minus its centre, over the middle 60 % of the line.
double lineDepth(Float64List l, SynthLine w) {
  final dx = w.x1 - w.x0, dy = w.y1 - w.y0;
  final len = math.sqrt(dx * dx + dy * dy);
  final nx = -dy / len, ny = dx / len, off = 3 * w.sigma + 0.02;
  var sum = 0.0, n = 0;
  for (var t = 0.2; t <= 0.8; t += 0.02) {
    final x = w.x0 + dx * t, y = w.y0 + dy * t;
    final c = _face.toPx(x, y);
    final a = _face.toPx(x + nx * off, y + ny * off);
    final b = _face.toPx(x - nx * off, y - ny * off);
    sum +=
        (discMean(l, _w, a.x, a.y, 1) + discMean(l, _w, b.x, b.y, 1)) / 2 -
        discMean(l, _w, c.x, c.y, 1);
    n++;
  }
  return sum / n;
}

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;
  late Float64List inL;

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
    inL = labOf(p.image).l;
  });

  Float64List run(Map<String, double> values) {
    var s = PortraitSettings.empty;
    for (final e in values.entries) {
      s = s.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    return labOf(
      applyRetouch(p.image, maps, RetouchUniforms.fromSettings(s, p.analysis)),
    ).l;
  }

  test('the fixture lines are real valleys', () {
    for (final w in kWrinkles) {
      expect(lineDepth(inL, w), greaterThan(0.018), reason: '${w.zone}');
    }
  });

  group('each zone slider', () {
    for (final zone in SynthZone.values) {
      test('${zone.name} 100 softens its lines and no others', () {
        final out = run({_zoneIds[zone]!: 100});
        final own = <double>[];
        for (final w in kWrinkles) {
          final r = lineDepth(out, w) / lineDepth(inL, w);
          if (w.zone == zone) {
            own.add(r);
            // Softened, never erased: at most 65 % goes (09 §4.10).
            expect(
              r,
              inInclusiveRange(0.3, 0.7),
              reason: '${w.zone} (${w.x0}, ${w.y0})',
            );
          } else if (identical(w, kWrinkles.first) && zone == SynthZone.frown) {
            // This forehead line crosses the frown zone on purpose: its
            // middle blends toward the frown slider.
            expect(r, inInclusiveRange(0.6, 0.98));
          } else {
            expect(r, greaterThan(0.9), reason: '${w.zone} (${w.x0}, ${w.y0})');
          }
        }
        expect(own.reduce((a, b) => a + b) / own.length, lessThan(0.65));
      });
    }
  });

  test('a zone slider is linear: 50 removes about half of 100', () {
    final w = kWrinkles.firstWhere((l) => l.zone == SynthZone.smile);
    final d0 = lineDepth(inL, w);
    final d50 = lineDepth(run({PortraitIds.wrinkleSmile: 50}), w);
    final d100 = lineDepth(run({PortraitIds.wrinkleSmile: 100}), w);
    expect((d0 - d50) / (d0 - d100), closeTo(0.5, 0.12));
  });

  test('pores continue through a softened line', () {
    final out = run({PortraitIds.wrinkleSmile: 100});
    final w = kWrinkles.firstWhere((l) => l.zone == SynthZone.smile);
    final fineIn = blur(inL, _w, _h, 1.0), fineOut = blur(out, _w, _h, 1.0);
    double energy(Float64List l, Float64List b, double from, double to) {
      var sum = 0.0, n = 0;
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          final q = _face.toLocal(x + 0.5, y + 0.5);
          final d = w.distance(q.x, q.y);
          final t = ((q.y - w.y0) / (w.y1 - w.y0));
          if (d < from || d > to || t < 0.2 || t > 0.8) continue;
          final i = y * _w + x;
          sum += math.pow(l[i] - b[i], 2);
          n++;
        }
      }
      return sum / n;
    }

    final onLine = energy(out, fineOut, 0, 1.2 * w.sigma);
    final beside = energy(inL, fineIn, 0.05, 0.08);
    expect(onLine / beside, greaterThan(0.5));
  });

  test('neighbouring zones blend: no seam between forehead and frown', () {
    final params = RetouchUniforms.fromSettings(
      PortraitSettings.empty
          .withGroupValue(FaceGroup.all, PortraitIds.wrinkleForehead, 100)
          .withGroupValue(FaceGroup.all, PortraitIds.wrinkleFrown, 0),
      p.analysis,
    ).row(0);
    final line = kWrinkles.first; // y = −0.62 crosses the frown zone
    expect(line.zone, SynthZone.forehead);
    final row = _face.toPx(0, line.y0).y;
    double? prev;
    var maxStep = 0.0, minW = 1.0, maxW = 0.0;
    for (var x = _face.toPx(-0.3, 0).x; x <= _face.toPx(0.3, 0).x; x += 1) {
      final code = maps.sourceNearest(
        RetouchChannel.wrinkleZone,
        (x + 0.5) / _w,
        (row + 0.5) / _h,
      );
      if (code == 0) continue;
      final wt = params.wrinkleWeight(code);
      minW = math.min(minW, wt);
      maxW = math.max(maxW, wt);
      if (prev != null) maxStep = math.max(maxStep, (wt - prev).abs());
      prev = wt;
    }
    expect(maxW, closeTo(1, 0.02), reason: 'pure forehead at the ends');
    expect(minW, lessThan(0.6), reason: 'frown share in the middle');
    expect(maxStep, lessThan(0.15), reason: 'blends over several texels');
  });

  test('only wrinkle valleys are filled', () {
    double dw(double x, double y) {
      final q = _face.toPx(x, y);
      return regionAt(
            maps,
            RetouchChannel.wrinkle,
            q.x.floor(),
            q.y.floor(),
            _w,
            _h,
          ) *
          kWrinkleRangeL;
    }

    // Features, the cheek stripe and blemishes inside a zone stay untouched.
    for (final (x, y) in [
      (-0.5, -0.33), // brow
      (-0.5, 0.0), // eye
      (0.0, 1.03), // lip
      (kStripeX, 0.8), // stripe (no zone)
      (0.30, -0.70), // acne on the forehead
      (-0.25, -0.70), // freckle on the forehead
    ]) {
      expect(dw(x, y), lessThan(0.002), reason: '$x, $y');
    }
    // Forehead pores away from the lines: almost never a fill.
    var hits = 0, total = 0;
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final q = _face.toLocal(x + 0.5, y + 0.5);
        if (q.y < -1.0 || q.y > -0.5 || q.x.abs() > 0.5) continue;
        if (wrinkleDistance(q.x, q.y) < 0.05) continue;
        if ([...kAcneSpots, ...kFreckleSpots].any(
          (s) =>
              math.sqrt(math.pow(s.x - q.x, 2) + math.pow(s.y - q.y, 2)) < 0.06,
        )) {
          continue;
        }
        total++;
        if (regionAt(maps, RetouchChannel.wrinkle, x, y, _w, _h) *
                kWrinkleRangeL >
            0.004) {
          hits++;
        }
      }
    }
    expect(hits / total, lessThan(0.01));
  });

  test('Smooth alone softens detected lines by its share only', () {
    final out = run({PortraitIds.skinSoftening: 100});
    for (final w in kWrinkles.where((l) => l.zone == SynthZone.smile)) {
      final r = lineDepth(out, w) / lineDepth(inL, w);
      // 0.65 · 0.3 of the detected line plus the band reduction.
      expect(r, inInclusiveRange(0.5, 0.9));
    }
  });

  test('Texture +100 does not deepen detected wrinkles', () {
    final out = run({PortraitIds.skinTexture: 100});
    for (final w in kWrinkles.where(
      (l) => l.zone == SynthZone.smile || l.zone == SynthZone.frown,
    )) {
      final r = lineDepth(out, w) / lineDepth(inL, w);
      expect(r, inInclusiveRange(0.9, 1.15), reason: '${w.zone}');
    }
  });

  test('zone weights decode as documented', () {
    double wt(int code) => wrinkleZoneWeight(
      code,
      forehead: 0.2,
      frown: 0.8,
      crowsFeet: 0.5,
      smile: 0.1,
      marionette: 0.9,
    );
    expect(wt(0), 0);
    expect(wt(kZoneCodeForehead), closeTo(0.2, 1e-12));
    expect(wt(kZoneCodeForehead + kZoneBlendSteps), closeTo(0.8, 1e-12));
    expect(wt(kZoneCodeSmile), closeTo(0.1, 1e-12));
    expect(wt(kZoneCodeSmile + kZoneBlendSteps), closeTo(0.9, 1e-12));
    expect(wt(kZoneCodeCrowsFeet), 0.5);
    expect(wt(200), 0);
    expect(decodeWrinkle(encodeWrinkle(0.05).toDouble()), closeTo(0.05, 4e-4));
    expect(encodeWrinkle(-0.01), 0);
  });
}
