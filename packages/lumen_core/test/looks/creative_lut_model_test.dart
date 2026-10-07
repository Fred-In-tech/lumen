import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'preset_fixtures.dart';

RgbaBuffer _ramp(int w, int h) {
  final b = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      b.data[o] = (x * 255 / (w - 1)).round();
      b.data[o + 1] = (y * 255 / (h - 1)).round();
      b.data[o + 2] = ((x + y) * 255 / (w + h - 2)).round();
      b.data[o + 3] = 255;
    }
  }
  return b;
}

int _maxDiff(RgbaBuffer a, RgbaBuffer b) {
  var m = 0;
  for (var i = 0; i < a.data.length; i++) {
    final d = (a.data[i] - b.data[i]).abs();
    if (d > m) m = d;
  }
  return m;
}

void main() {
  final lut = tealOrangeLut();
  final ref = LutRef(hash: lut.contentHash, name: lut.title);

  group('LutRef', () {
    test('JSON round trip and validation', () {
      final r = ref.copyWith(amount: 140);
      expect(r.amount, 100);
      expect(LutRef.fromJson(r.toJson()), r);
      expect(LutRef.fromJson({'hash': 'nothex', 'name': 'x'}), isNull);
      expect(LutRef.fromJson('x'), isNull);
      final loose = LutRef.fromJson({'hash': ref.hash, 'name': ' '})!;
      expect(loose.name, 'LUT');
      expect(loose.amount, 100);
      expect(LutRef.clampAmount(double.nan), 100);
      expect(ref.toString(), contains(ref.hash));
    });
  });

  group('DevelopSettings.lut', () {
    test('JSON, equality, isDefault', () {
      final s = DevelopSettings.defaults.withLut(ref.copyWith(amount: 60));
      expect(s.isDefault, isFalse);
      final back = DevelopSettings.fromJson(s.toJson());
      expect(back, s);
      expect(back.hashCode, s.hashCode);
      expect(back.lut!.amount, 60);
      expect(s.withLut(null).isDefault, isTrue);
      expect(DevelopSettings.defaults.toJson().containsKey('lut'), isFalse);
      // Other edits keep the LUT.
      expect(s.withValue(P.exposure, 1).lut, s.lut);
      expect(s.copyWith(treatment: Treatment.bw).lut, s.lut);
    });

    test('history records and undoes LUT changes', () {
      final a = DevelopSettings.defaults;
      final b = a.withLut(ref);
      final h = HistoryEntry.tryDiff(
        label: 'LUT',
        kind: HistoryKind.preset,
        before: a,
        after: b,
      )!;
      expect(h.ops.single.path, 'lut');
      final stack = HistoryStack.empty.push(h);
      expect(stack.undo(b).settings.lut, isNull);
    });

    test('copy / paste carries the LUT with its group', () {
      final src = DevelopSettings.defaults.withLut(ref);
      final kept = pasteSettings(
        source: src,
        target: DevelopSettings.defaults,
        groups: {SettingsGroup.light},
      );
      expect(kept.lut, isNull);
      final pasted = pasteSettings(
        source: src,
        target: DevelopSettings.defaults,
        groups: {SettingsGroup.lut},
      );
      expect(pasted.lut, ref);
      expect(SettingsGroup.defaultCopy, contains(SettingsGroup.lut));
      expect(SettingsGroup.lut.label, 'Creative LUT');
    });
  });

  group('Preset with LUT, source and partial curves', () {
    test('LUT applies at its amount × preset amount', () {
      final p = Preset(
        id: 'p',
        name: 'Teal',
        values: const {},
        lut: ref.copyWith(amount: 80),
        source: PresetSource.lut,
      );
      expect(p.isLutOnly, isTrue);
      expect(p.adjustmentCount, 1);
      final full = p.apply(DevelopSettings.defaults);
      expect(full.lut!.amount, 80);
      final half = p.apply(DevelopSettings.defaults, amount: 0.5);
      expect(half.lut!.amount, 40);
      expect(p.apply(DevelopSettings.defaults, amount: 0).lut, isNull);
    });

    test('partial curves leave the other channels alone', () {
      final current = DevelopSettings.defaults.copyWith(
        curves: const CurveSet(
          red: ToneCurve([CurvePoint(0, 10), CurvePoint(255, 255)]),
        ),
      );
      final p = Preset(
        id: 'p',
        name: 'Blue curve',
        values: const {},
        curves: const CurveSet(
          blue: ToneCurve([CurvePoint(0, 20), CurvePoint(255, 240)]),
        ),
        curveChannels: {CurveChannel.blue},
      );
      final out = p.apply(current);
      expect(out.curves.red, current.curves.red);
      expect(out.curves.blue.evaluate(0), 20);
      final all = Preset(
        id: 'q',
        name: 'All',
        values: const {},
        curves: const CurveSet(
          blue: ToneCurve([CurvePoint(0, 20), CurvePoint(255, 240)]),
        ),
      );
      expect(all.apply(current).curves.red.isIdentity, isTrue);
    });

    test('JSON round trip keeps source, report, lut and channels', () {
      final p = Preset(
        id: 'lr.1',
        name: 'Moody',
        group: 'Film',
        values: const {P.exposure: -0.3},
        curves: const CurveSet(
          blue: ToneCurve([CurvePoint(0, 20), CurvePoint(255, 240)]),
        ),
        curveChannels: {CurveChannel.blue},
        lut: ref,
        source: PresetSource.lightroom,
        importReport: const PresetImportReport(
          fileName: 'Moody.xmp',
          applied: ['Exposure'],
          approximated: ['White balance'],
          skipped: ['Calibration'],
        ),
      );
      final back = Preset.fromJson(p.toJson());
      expect(back, p);
      expect(back.importReport, p.importReport);
      expect(back.importReport.hashCode, p.importReport.hashCode);
      expect(back.copyWith(name: 'New').lut, ref);
      expect(back.copyWith(group: 'G').importReport, p.importReport);
      // Older files: no source → user / built-in.
      expect(Preset.fromJson({'name': 'x'}).source, PresetSource.user);
      expect(
        Preset.fromJson({'name': 'x', 'builtIn': true}).source,
        PresetSource.builtIn,
      );
      expect(
        PresetImportReport.fromJson('x'),
        const PresetImportReport(fileName: ''),
      );
    });

    test('from settings includes the LUT', () {
      final s = DevelopSettings.defaults.withLut(ref);
      expect(Preset.fromSettings(id: 'a', name: 'a', settings: s).lut, ref);
    });
  });

  group('LUT stage in the CPU twin', () {
    final src = _ramp(32, 24);

    test('packs size and amount only when a LUT is bound', () {
      final s = DevelopSettings.defaults.withLut(ref.copyWith(amount: 50));
      DevelopContext ctx(int n) => DevelopContext(
        outWidth: 4,
        outHeight: 4,
        sourceWidth: 4,
        sourceHeight: 4,
        auxWidth: 1,
        auxHeight: 1,
        lutSize: n,
      );
      final on = DevelopUniforms.pack(s, ctx(17));
      expect(on[DevelopIndex.lutSize], 17);
      expect(on[DevelopIndex.lutAmount], 0.5);
      final off = DevelopUniforms.pack(s, ctx(0));
      expect(off[DevelopIndex.lutAmount], 0);
      final none = DevelopUniforms.pack(DevelopSettings.defaults, ctx(17));
      expect(none[DevelopIndex.lutAmount], 0);
    });

    test('identity LUT and amount 0 change nothing', () {
      final plain = renderReference(src, DevelopSettings.defaults);
      final id = CubeLut.identity(33);
      final s = DevelopSettings.defaults.withLut(
        LutRef(hash: id.contentHash, name: 'id'),
      );
      expect(
        _maxDiff(renderReference(src, s, creativeLut: id), plain),
        lessThanOrEqualTo(1),
      );
      final zero = DevelopSettings.defaults.withLut(ref.copyWith(amount: 0));
      expect(_maxDiff(renderReference(src, zero, creativeLut: lut), plain), 0);
    });

    test('a missing or mismatched LUT renders without the stage', () {
      final plain = renderReference(src, DevelopSettings.defaults);
      final s = DevelopSettings.defaults.withLut(ref);
      expect(_maxDiff(renderReference(src, s), plain), 0);
      final other = CubeLut.identity(5);
      expect(_maxDiff(renderReference(src, s, creativeLut: other), plain), 0);
    });

    test('the look applies, scaled by amount, on both paths', () {
      final plain = renderReference(src, DevelopSettings.defaults);
      final full = renderReference(
        src,
        DevelopSettings.defaults.withLut(ref),
        creativeLut: lut,
      );
      final half = renderReference(
        src,
        DevelopSettings.defaults.withLut(ref.copyWith(amount: 50)),
        creativeLut: lut,
      );
      final dFull = _maxDiff(full, plain);
      final dHalf = _maxDiff(half, plain);
      expect(dFull, greaterThan(8));
      expect(dHalf, inInclusiveRange(dFull ~/ 2 - 2, dFull ~/ 2 + 2));
      // Exactly the LUT sample at a pixel (defaults: develop is identity).
      final out = Float64List(3);
      const x = 20, y = 5;
      final o = (y * 32 + x) * 4;
      lut.sample(
        src.data[o] / 255,
        src.data[o + 1] / 255,
        src.data[o + 2] / 255,
        out,
      );
      for (var c = 0; c < 3; c++) {
        expect(full.data[o + c], closeTo(out[c] * 255, 1));
      }
      // Float path, 8-bit-equivalent input: same bytes.
      final f = renderReferenceFloat(
        FloatBuffer.fromRgba(src),
        DevelopSettings.defaults.withLut(ref),
        creativeLut: lut,
      ).toRgba();
      expect(_maxDiff(f, full), lessThanOrEqualTo(1));
    });
  });
}
