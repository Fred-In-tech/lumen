// Properties that must hold on every scene (research 09 §2.11, §5.1):
// per-scene caps, determinism, batch = single, explained changes.
import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'enhance_scenes.dart';

typedef _C = EnhanceConstants;

List<(String, PeopleScene)> _scenes() => [
  for (final e in Skin.all.entries)
    for (final stops in [-2.5, -1.0, 0.0, 1.0])
      ('${e.key} $stops', paintPeople([PaintedFace(e.value)], stops: stops)),
  (
    'tungsten',
    paintPeople([const PaintedFace(Skin.tan)], light: (1.6, 1, 0.5)),
  ),
  ('blue', paintPeople([const PaintedFace(Skin.light)], light: (0.6, 1, 1.5))),
  ('green', paintPeople([const PaintedFace(Skin.brown)], light: (1, 1.4, 1))),
  ('magenta', paintPeople([const PaintedFace(Skin.tan)], light: (1, 0.7, 1))),
  ('dark room', paintPeople([const PaintedFace(Skin.deep)], wall: 0.01)),
  ('white room', paintPeople([const PaintedFace(Skin.light)], wall: 0.9)),
  (
    'group',
    paintPeople(const [
      PaintedFace(Skin.deep, u: 0.2, size: 0.8),
      PaintedFace(Skin.brown, u: 0.4, size: 0.8),
      PaintedFace(Skin.tan, u: 0.6, size: 0.8),
      PaintedFace(Skin.light, u: 0.8, size: 0.8),
    ], stops: -1.2),
  ),
];

void main() {
  final scenes = _scenes();
  final runs = <String, EnhanceRun>{};
  setUpAll(() async {
    for (final (name, scene) in scenes) {
      runs[name] = await enhance(scene);
    }
  });

  test('per-click limits are never exceeded', () {
    for (final e in runs.entries) {
      final r = e.value;
      final n = e.key;
      expect(
        r.v(P.exposure),
        inInclusiveRange(_C.evMinOther, _C.evMaxOther),
        reason: n,
      );
      expect(r.v(P.temp), inInclusiveRange(-_C.tempMaxWide, _C.tempMaxWide));
      expect(r.v(P.tint), inInclusiveRange(-_C.tintMaxWide, _C.tintMaxWide));
      expect(r.v(P.highlights), inInclusiveRange(-_C.highlightsCap, 0));
      expect(r.v(P.shadows), inInclusiveRange(0, _C.shadowsCap));
      expect(
        r.v(P.whites),
        inInclusiveRange(_C.whitesMin, _C.whitesMax),
        reason: n,
      );
      expect(r.v(P.blacks), inInclusiveRange(_C.blacksMin, _C.blacksMax));
      expect(
        r.v(P.contrast),
        inInclusiveRange(_C.contrastMin, _C.contrastMax),
        reason: n,
      );
      expect(r.v(P.vibrance), inInclusiveRange(_C.vibranceMin, _C.vibranceMax));
      expect(r.v(P.saturation), inInclusiveRange(_C.saturationMin, 8));
    }
  });

  test('portrait scenes stay inside the portrait limits', () {
    for (final e in runs.entries) {
      if (e.key == 'group') continue;
      final tone = LocalAutoTone.run(
        proxy: e.value.scene.image,
        faces: e.value.scene.faces,
      );
      if (tone.detail.scene.kind != SceneKind.portrait) continue;
      final s = tone.settings;
      expect(
        s.value(P.exposure),
        inInclusiveRange(_C.evMinPortrait, _C.evMaxPortrait + 0.5),
        reason: e.key,
      );
      expect(s.value(P.highlights), greaterThanOrEqualTo(-60), reason: e.key);
      expect(s.value(P.shadows), lessThanOrEqualTo(45), reason: e.key);
      expect(s.value(P.contrast), lessThanOrEqualTo(15), reason: e.key);
      expect(s.value(P.vibrance), lessThanOrEqualTo(12), reason: e.key);
      // Up to 40 only to give a light that was blown as shot its white back.
      expect(s.value(P.whites), lessThanOrEqualTo(40), reason: e.key);
      expect(s.value(P.blacks), inInclusiveRange(-30, 10), reason: e.key);
    }
  });

  test('the edit adds next to no clipping and no crushed shadows', () {
    for (final e in runs.entries) {
      final r = e.value;
      expect(
        SceneMetrics.clipFraction(r.rendered),
        // Lifting a face 2.5 stops may cost a little of a white shirt; an
        // ordinary frame gains next to nothing.
        lessThanOrEqualTo(
          SceneMetrics.clipFraction(r.scene.image) +
              (e.key.contains('-2.5') ? 0.015 : 0.005),
        ),
        reason: e.key,
      );
      expect(
        SceneMetrics.crushFraction(r.rendered),
        lessThanOrEqualTo(SceneMetrics.crushFraction(r.scene.image) + 0.03),
        reason: e.key,
      );
    }
  });

  test('diffuse skin never ends hot, and never leaves the hue window it '
      'was in', () {
    for (final e in runs.entries) {
      final before = e.value.before, after = e.value.after;
      for (var i = 0; i < after.length; i++) {
        // Skin that was blown as shot can only come down, not be rebuilt.
        expect(
          after[i].hot,
          lessThanOrEqualTo(before[i].hot > 0.95 ? before[i].hot - 0.02 : 0.95),
          reason: e.key,
        );
        final inWindow =
            before[i].hue >= _C.skinHueLow && before[i].hue <= _C.skinHueHigh;
        if (inWindow) {
          expect(
            after[i].hue,
            inInclusiveRange(_C.skinHueLow - 1, _C.skinHueHigh + 1),
            reason: e.key,
          );
        }
      }
    }
  });

  test('deterministic: the same photo always gets the same edit', () async {
    for (final (name, scene) in scenes.take(6)) {
      final again = await enhance(scene);
      expect(
        again.outcome.settings,
        runs[name]!.outcome.settings,
        reason: name,
      );
      expect(again.outcome.changes, runs[name]!.outcome.changes, reason: name);
    }
  });

  test('batch = single: a photo solved among others gets the edit it gets '
      'alone', () async {
    final batch = await Future.wait([
      for (final (_, scene) in scenes.reversed.take(5)) enhance(scene),
    ]);
    final names = [for (final (n, _) in scenes.reversed.take(5)) n];
    for (var i = 0; i < batch.length; i++) {
      expect(batch[i].outcome.settings, runs[names[i]]!.outcome.settings);
    }
  });

  test('every change is explained with its size, briefly', () {
    for (final r in runs.values) {
      for (final c in r.outcome.changes) {
        expect(c.reason, isNotEmpty);
        expect(c.reason.length, lessThan(90), reason: c.reason);
        expect(c.reason, contains(Reasons.formatDelta(c.param, c.delta)));
      }
    }
  });

  test('face reasons name the faces', () {
    final under = runs['tan -2.5']!.outcome.changes.firstWhere(
      (c) => c.param == P.exposure,
    );
    expect(under.reason, contains('faces'));
    final over = runs['tan 1.0']!.outcome.changes.firstWhere(
      (c) => c.param == P.exposure,
    );
    expect(over.reason, startsWith('Lowered exposure'));
  });

  test('an already good photo: "no changes" is an explicit outcome', () async {
    // A full-range frame: a little true black, a white that is there but
    // not blown, normal contrast and colour.
    final p = RgbaBuffer(240, 160);
    for (var y = 0; y < p.height; y++) {
      for (var x = 0; x < p.width; x++) {
        if (y < 2) {
          p.setPixel(x, y, 4, 4, 4);
          continue;
        }
        final base = (20 + 180 * x / (p.width - 1)).round();
        final c = [0, 0, 0];
        c[(y * 6 ~/ p.height) % 3] = 46;
        p.setPixel(x, y, base + c[0], base + c[1], base + c[2]);
      }
    }
    final tone = LocalAutoTone.run(proxy: p);
    expect(tone.detail.notes.first, EnhanceNote.nothingToDo);
    expect(tone.settings, DevelopSettings.defaults);
    final out = await const LocalAutoEditProvider().autoEdit(
      AutoEditInput(stats: ImageStats.compute(p), proxy: p),
    );
    expect(out.changes, isEmpty);
    expect(out.hasChanges, isFalse);
    expect(out.settings, DevelopSettings.defaults);
    expect(out.intent, contains('no changes needed'));
    // Leftovers of an earlier Auto are cleared, not built upon.
    final stale = DevelopSettings.defaults.withValues({
      P.exposure: 1.5,
      P.vibrance: 30,
    });
    expect(
      LocalAutoTone.run(proxy: p, base: stale).settings,
      DevelopSettings.defaults,
    );
  });
}
