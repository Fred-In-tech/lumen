import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

/// The same face at two image sizes (re-analysis at another `Rres`).
SynthPortrait _render(int size) {
  final s = size / 512;
  return renderSynthPortrait(size, size, [
    SynthFace(id: 'a', cx: 256 * s, cy: 200 * s, iod: 140 * s),
  ]);
}

BlemishCandidate _near(RetouchMaps m, SynthSpot s, SynthFace f, int size) {
  final c = f.toPx(s.x, s.y);
  return m.blemishes.reduce((a, b) {
    double d(BlemishCandidate x) => math.sqrt(
      math.pow(x.u * size - c.x, 2) + math.pow(x.v * size - c.y, 2),
    );
    return d(a) <= d(b) ? a : b;
  });
}

void main() {
  test('anchors round-trip through JSON (rounded)', () {
    const a = SpotAnchor(0.4183219, 0.3120934, 0.0261234);
    final b = SpotAnchor.fromJson(a.toJson());
    expect(b.u, closeTo(a.u, 1e-5));
    expect(b.v, closeTo(a.v, 1e-5));
    expect(b.radiusIod, closeTo(a.radiusIod, 1e-3));
    expect(SpotAnchor.fromJson(b.toJson()), b);
  });

  group('across re-analysis at another size', () {
    late SynthPortrait small, large;
    late RetouchMaps mSmall, mLarge;
    setUpAll(() {
      small = _render(512);
      large = _render(640);
      mSmall = computeRetouchMaps(small.image, small.analysis);
      mLarge = computeRetouchMaps(large.image, large.analysis);
    });

    test('candidate ids change, anchor positions match', () {
      final ids = mLarge.blemishes.map((b) => b.id).toSet();
      final same = mSmall.blemishes.where((b) => ids.contains(b.id)).length;
      expect(same, lessThan(mSmall.blemishes.length ~/ 2));
      for (final s in kDefaultSpots) {
        final a = SpotAnchor.of(_near(mSmall, s, small.faces.first, 512));
        final b = _near(mLarge, s, large.faces.first, 640);
        final d = math.sqrt(
          math.pow((a.u - b.u) * 640, 2) + math.pow((a.v - b.v) * 640, 2),
        );
        final tol =
            (kAnchorMatchIod + 0.5 * math.max(a.radiusIod, b.radiusIod)) *
            large.faces.first.iod;
        expect(d, lessThan(tol), reason: '${s.kind} at ${s.x}, ${s.y}');
      }
    });

    test('keep / remove anchors from the small analysis act on the large', () {
      final f = large.faces.first;
      final acne = kAcneSpots.first, freckle = kFreckleSpots.first;
      final o = BlemishOverrides(
        keepAt: [SpotAnchor.of(_near(mSmall, acne, small.faces.first, 512))],
        removeAt: [
          SpotAnchor.of(_near(mSmall, freckle, small.faces.first, 512)),
        ],
      );
      final m = computeRetouchMaps(large.image, large.analysis, overrides: o);
      final out = labOf(
        applyRetouch(
          large.image,
          m,
          RetouchUniforms.fromSettings(
            PortraitSettings.empty.withGroupValue(
              FaceGroup.all,
              PortraitIds.acne,
              100,
            ),
            large.analysis,
          ),
        ),
      );
      final before = labOf(large.image);
      double contrast(Float64List p, SynthSpot s) {
        final c = f.toPx(s.x, s.y), r = s.radius * f.iod;
        return (discMean(p, 640, c.x, c.y, 0.5 * r) -
                ringMean(p, 640, c.x, c.y, 2 * r, 3 * r))
            .abs();
      }

      expect(
        contrast(out.a, acne) / contrast(before.a, acne),
        greaterThan(0.9),
      );
      expect(
        contrast(out.l, freckle) / contrast(before.l, freckle),
        lessThan(0.3),
      );
    });
  });

  test('an unmatched remove anchor heals its disc as a manual spot', () {
    final p = _render(512);
    final f = p.faces.first;
    final spot = f.toPx(0.10, 0.25); // clean cheek next to the nose
    final o = BlemishOverrides(
      removeAt: [SpotAnchor(spot.x / 512, spot.y / 512, 0.02)],
      keepAt: [SpotAnchor(spot.x / 512 + 0.2, spot.y / 512, 0.02)],
    );
    final m = computeRetouchMaps(p.image, p.analysis, overrides: o);
    final manual = m.blemishes.where((b) => b.id.startsWith('manual:'));
    expect(manual, hasLength(1));
    final code = m.nearest(RetouchChannel.spotCode, spot.x / 512, spot.y / 512);
    expect(spotSelection(code, 0, 0, 0), 1, reason: 'forced');
  });
}
