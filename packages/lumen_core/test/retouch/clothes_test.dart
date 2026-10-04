import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_backdrop.dart';
import 'support/synthetic_clothes.dart';

typedef _Lab = ({Float64List l, Float64List a, Float64List b});

void main() {
  late ClothesScene s;
  late RetouchMaps maps;
  late _Lab input;
  late Float64List refBlur;
  late Float64List inBlur;

  setUpAll(() {
    s = renderClothesScene();
    maps = computeRetouchMaps(s.image, s.analysis, backdrop: s.input);
    input = labOf(s.image);
    refBlur = blur(
      labOf(renderClothesScene(folds: false).image).l,
      s.width,
      s.height,
      1.5,
    );
    inBlur = blur(input.l, s.width, s.height, 1.5);
  });

  RetouchUniforms values(double wrinkles, double lint) =>
      RetouchUniforms.fromSettings(
        PortraitSettings.empty
            .withImageValue(PortraitIds.clothesWrinkles, wrinkles)
            .withImageValue(PortraitIds.clothesLint, lint),
        s.analysis,
      );

  RgbaBuffer run(double wrinkles, double lint) =>
      applyRetouch(s.image, maps, values(wrinkles, lint));

  bool nearLint(double x, double y, double r) => s.lint.any(
    (p) => math.sqrt(math.pow(x - p.x, 2) + math.pow(y - p.y, 2)) < r,
  );

  /// Shirt pixels away from the seam, the panel edge, the lint and the
  /// shirt outline (the fold metrics' domain).
  bool open(int i) {
    final w = s.width, x = i % w + 0.5, y = i ~/ w + 0.5;
    return s.isShirt(x, y, 14) &&
        (x - kSeamX * w).abs() >= 25 &&
        (x - kPanelX * w).abs() >= 25 &&
        !nearLint(x, y, 8);
  }

  /// Mean |fold left| over pixels within 1.5 σ of a fold ridge.
  double foldLeft(Float64List l) {
    final w = s.width, b = blur(l, w, s.height, 1.5);
    return meanWhere(
      l.length,
      (i) =>
          open(i) &&
          s.foldDistance(i % w + 0.5, i ~/ w + 0.5) < 1.5 * kFoldSigma,
      (i) => (b[i] - refBlur[i]).abs(),
    );
  }

  /// Fine fabric texture (L minus its σ 1.5 blur, std) away from folds.
  double texture(Float64List l, Float64List b) {
    final w = s.width, n = l.length;
    bool flat(int i) =>
        open(i) && s.foldDistance(i % w + 0.5, i ~/ w + 0.5) > 3 * kFoldSigma;
    final m = meanWhere(n, flat, (i) => l[i] - b[i]);
    return math.sqrt(
      meanWhere(n, flat, (i) => math.pow(l[i] - b[i] - m, 2).toDouble()),
    );
  }

  /// Seam depth: centre column minus its neighbours 5 px aside.
  double seam(Float64List l) {
    final w = s.width, xs = (kSeamX * w).floor();
    var acc = 0.0, c = 0;
    for (var y = (0.4 * s.height).floor(); y < (0.95 * s.height).floor(); y++) {
      acc += l[y * w + xs] - 0.5 * (l[y * w + xs - 5] + l[y * w + xs + 5]);
      c++;
    }
    return acc / c;
  }

  /// Panel step: 3–8 px right of the panel edge minus 3–8 px left of it.
  double panel(Float64List l) {
    final w = s.width, xp = (kPanelX * w).floor();
    var acc = 0.0, c = 0;
    for (var y = (0.4 * s.height).floor(); y < (0.95 * s.height).floor(); y++) {
      for (var k = 3; k <= 8; k++) {
        acc += l[y * w + xp + k] - l[y * w + xp - k];
        c++;
      }
    }
    return acc / c;
  }

  /// Speck contrast against the fabric ring around it.
  double speck(Float64List l, Lint p) =>
      discMean(l, s.width, p.x, p.y, p.r) -
      ringMean(l, s.width, p.x, p.y, p.r + 3, p.r + 6);

  group('clothing wrinkles', () {
    test('the maps are built on the clothes raster', () {
      final b = maps.backdrop;
      expect(b.clothesState, ClothesState.ready);
      expect(b.clothesState.reason, isNull);
      expect(b.state, BackdropState.notRequested);
      expect(maps.hasClothes, isTrue);
      expect(maps.hasBackdrop, isFalse);
      expect(maps.isUsable, isTrue);
      expect(b.atlas, hasLength(24 * b.width * b.height));
    });

    test('soft folds are mostly removed, scaled by the slider', () {
      final before = foldLeft(input.l);
      expect(before, greaterThan(0.015));
      final full = foldLeft(labOf(run(100, 0)).l);
      final half = foldLeft(labOf(run(50, 0)).l);
      expect(full / before, lessThan(0.35));
      expect(half / before, inInclusiveRange(0.45, 0.75));
    });

    test('seams, panel edges and fabric texture are kept', () {
      final out = labOf(run(100, 0)).l;
      expect(seam(out) / seam(input.l), greaterThan(0.95));
      expect(panel(out) / panel(input.l), greaterThan(0.95));
      final outBlur = blur(out, s.width, s.height, 1.5);
      expect(
        texture(out, outBlur) / texture(input.l, inBlur),
        greaterThan(0.95),
      );
    });

    test('wrinkles leave lint alone', () {
      final out = labOf(run(100, 0)).l;
      for (final p in s.lint) {
        expect(speck(out, p) / speck(input.l, p), greaterThan(0.9));
      }
    });

    test('pixels off the clothes are untouched (bit-exact)', () {
      final out = run(100, 100);
      final top = ((kShirtTop * s.height).floor() - 10) * s.width * 4;
      expect(out.data.sublist(0, top), s.image.data.sublist(0, top));
    });

    test('the change is linear in the slider (uniform-only drags)', () {
      final full = labOf(run(100, 0)), half = labOf(run(50, 0));
      final w = s.width;
      for (final (x, y) in [
        (w * 0.30, s.height * 0.7),
        (w * 0.5, s.height * 0.6),
      ]) {
        final i = y.floor() * w + x.floor();
        expect(
          half.l[i] - input.l[i],
          closeTo(0.5 * (full.l[i] - input.l[i]), 0.006),
        );
      }
    });
  });

  group('lint & specks', () {
    test('specks on the fabric are healed', () {
      final out = labOf(run(0, 100)).l;
      for (final p in s.lint) {
        expect(
          speck(out, p).abs() / speck(input.l, p).abs(),
          lessThan(0.15),
          reason: '$p',
        );
      }
    });

    test('nothing else changes: folds, seams, texture', () {
      final out = labOf(run(0, 100)).l;
      final w = s.width;
      for (var i = 0; i < out.length; i++) {
        if (nearLint(i % w + 0.5, i ~/ w + 0.5, 8)) continue;
        expect((out[i] - input.l[i]).abs(), lessThan(0.01));
      }
    });
  });

  group('states and laziness', () {
    test('identity values: the pass is off and the image unchanged', () {
      expect(RetouchPassUniforms.isActive(maps, values(0, 0)), isFalse);
      expect(identical(run(0, 0), s.image), isTrue);
    });

    test('no clothes raster: noMatte with a reason, sliders inert', () {
      final m = computeRetouchMaps(
        s.image,
        s.analysis,
        backdrop: const BackdropInput(wantsBackdrop: false, wantsClothes: true),
      );
      expect(m.backdrop.clothesState, ClothesState.noMatte);
      expect(m.backdrop.clothesState.reason, contains('clothes mask'));
      expect(m.hasClothes, isFalse);
      expect(RetouchPassUniforms.isActive(m, values(100, 100)), isFalse);
    });

    test('an empty clothes raster: noClothes with a reason', () {
      final empty = MaskRaster(
        s.clothes.width,
        s.clothes.height,
        Uint8List(s.clothes.width * s.clothes.height),
      );
      final m = computeRetouchMaps(
        s.image,
        s.analysis,
        backdrop: BackdropInput(
          clothes: empty,
          wantsBackdrop: false,
          wantsClothes: true,
        ),
      );
      expect(m.backdrop.clothesState, ClothesState.noClothes);
      expect(m.backdrop.clothesState.reason, contains('No clothing'));
      expect(m.hasClothes, isFalse);
    });

    test('clothes not requested: nothing is built for them', () {
      final m = computeRetouchMaps(
        s.image,
        s.analysis,
        backdrop: BackdropInput(clothes: s.clothes, wantsBackdrop: false),
      );
      expect(m.backdrop.clothesState, ClothesState.notRequested);
      expect(m.backdrop.clothesState.reason, isNull);
      expect(m.isUsable, isFalse);
    });

    test('backdrop and clothes share one atlas without touching each '
        'other', () {
      final b = renderBackdropScene();
      // The shoulders below 62 % are the clothes.
      final people = b.people;
      final cloth = Uint8List.fromList([
        for (var i = 0; i < people.data.length; i++)
          (i ~/ people.width) >= 0.64 * people.height ? people.data[i] : 0,
      ]);
      final clothes = MaskRaster(people.width, people.height, cloth);
      final both = computeBackdropMaps(
        b.image,
        BackdropInput(
          people: b.people,
          hair: b.hair,
          clothes: clothes,
          wantsClothes: true,
        ),
      );
      final only = computeBackdropMaps(b.image, b.input);
      expect(both.state, BackdropState.ready);
      expect(both.clothesState, ClothesState.ready);
      expect(only.clothesState, ClothesState.notRequested);
      expect([both.width, both.height], [only.width, only.height]);
      // Backdrop tiles (columns 0–1) are identical; the clothes column of
      // the backdrop-only atlas is neutral (128 = 0).
      final w = both.width, stride = kImageAtlasColumns * w * 4;
      for (var y = 0; y < kImageAtlasRows * both.height; y++) {
        final row = y * stride;
        expect(
          both.atlas.sublist(row, row + 2 * w * 4),
          only.atlas.sublist(row, row + 2 * w * 4),
        );
        for (var x = 2 * w; x < 3 * w; x++) {
          expect(only.atlas[row + x * 4], 128);
        }
      }
    });
  });
}
