import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  test('80 scalar params with unique ids', () {
    expect(ParamRegistry.all.length, 80);
    expect(ParamRegistry.all.map((p) => p.id).toSet().length, 80);
  });

  test('defaults lie within range and min < max', () {
    for (final p in ParamRegistry.all) {
      expect(p.min < p.max, isTrue, reason: p.id);
      expect(p.defaultValue, inInclusiveRange(p.min, p.max), reason: p.id);
      expect(p.step > 0, isTrue, reason: p.id);
      expect(p.xmp, isNotEmpty, reason: p.id);
      expect(p.label, isNotEmpty, reason: p.id);
    }
  });

  test('lookup and clamp', () {
    final e = ParamRegistry.byId(P.exposure);
    expect(e.min, -5);
    expect(e.clamp(9), 5);
    expect(ParamRegistry.byId('hsl.blue.sat').group, ParamGroup.hsl);
    expect(ParamRegistry.tryById('nope'), isNull);
    expect(() => ParamRegistry.byId('nope'), throwsArgumentError);
  });

  test('group sizes', () {
    int count(ParamGroup g) => ParamRegistry.inGroup(g).length;
    expect(count(ParamGroup.light), 6);
    expect(count(ParamGroup.color), 4);
    expect(count(ParamGroup.presence), 3);
    expect(count(ParamGroup.hsl), 24);
    expect(count(ParamGroup.bw), 8);
    expect(count(ParamGroup.curve), 7);
    expect(count(ParamGroup.grading), 14);
    expect(count(ParamGroup.detail), 6);
    expect(count(ParamGroup.effects), 8);
  });

  test('aiEditable excludes sharpen.radius only among scalars', () {
    final notAi = ParamRegistry.all
        .where((p) => !p.aiEditable)
        .map((p) => p.id);
    expect(notAi, ['sharpen.radius']);
    expect(ParamRegistry.aiEditableIds, contains(P.exposure));
  });

  test('hsl helper ids', () {
    expect(P.hsl(HslBand.aqua, HslChannel.lum), 'hsl.aqua.lum');
    expect(P.bw(HslBand.red), 'bw.red');
    expect(HslBand.values.length, 8);
  });
}
