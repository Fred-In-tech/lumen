import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _sample({List<Object?>? adjustments}) => {
  'scene': {
    'subject': 'portrait, outdoor cafe',
    'lighting': 'backlit',
    'timeOfDay': 'golden_hour',
    'keyIntent': 'normal',
  },
  'issues': [
    {'issue': 'face underexposed', 'severity': 'medium'},
  ],
  'intent': 'Warm, soft backlit portrait',
  'variants': [
    {
      'label': 'Moody',
      'confidence': 0.78,
      'targets': {
        'midLStar': 48,
        'wbStrength': 0.3,
        'contrastLevel': 'medium',
        'colorLevel': 'natural',
      },
      'presetAtoms': [
        {'atom': 'moody', 'amount': 0.7},
      ],
      'adjustments':
          adjustments ??
          [
            {'param': 'shadows', 'value': 28, 'reason': 'Open the face'},
          ],
    },
  ],
  'done': false,
};

void main() {
  group('AutoEditResponse.fromJson (tolerant)', () {
    test('parses the documented example', () {
      final r = AutoEditResponse.fromJson(_sample());
      expect(r.scene.timeOfDay, 'golden_hour');
      expect(r.issues.single.severity, 'medium');
      expect(r.intent, startsWith('Warm'));
      final v = r.variants.single;
      expect(v.label, 'Moody');
      expect(v.confidence, closeTo(0.78, 1e-9));
      expect(v.targets.midLStar, 48);
      expect(v.presetAtoms.single.atom, 'moody');
      expect(v.adjustments.single.param, P.shadows);
      expect(v.adjustments.single.value, 28);
      expect(r.done, isFalse);
    });

    test('drops unknown, non-editable and non-numeric params', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': 'teleport', 'value': 3, 'reason': 'x'},
            {'param': P.sharpenRadius, 'value': 2, 'reason': 'x'},
            {'param': P.contrast, 'value': 'lots', 'reason': 'x'},
            {'param': P.exposure, 'value': 0.4, 'reason': 'Brighter'},
            'garbage',
          ],
        ),
      );
      expect(r.variants.single.adjustments.map((a) => a.param), [P.exposure]);
    });

    test('later duplicate of a param wins', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': P.temp, 'value': 5, 'reason': 'a'},
            {'param': P.temp, 'value': 9, 'reason': 'b'},
          ],
        ),
      );
      final adj = r.variants.single.adjustments.single;
      expect(adj.value, 9);
      expect(adj.reason, 'b');
    });

    test('unknown enums fall back, unknown atoms dropped, garbage is '
        'survivable', () {
      final json = _sample();
      (json['scene']! as Map)['timeOfDay'] = 'teatime';
      ((json['variants']! as List).single as Map)['presetAtoms'] = [
        {'atom': 'neon', 'amount': 1},
        {'atom': 'warm', 'amount': 9},
      ];
      final r = AutoEditResponse.fromJson(json);
      expect(r.scene.timeOfDay, 'unknown');
      final atoms = r.variants.single.presetAtoms;
      expect(atoms.single.atom, 'warm');
      expect(atoms.single.amount, 2, reason: 'atom amount clamped to 0..2');
      expect(AutoEditResponse.fromJson('nope').variants, isEmpty);
      expect(AutoEditResponse.fromJson(null).done, isFalse);
    });

    test('NaN-free: non-finite numbers are dropped', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': P.exposure, 'value': double.infinity, 'reason': 'x'},
          ],
        ),
      );
      expect(r.variants.single.adjustments, isEmpty);
    });
  });

  group('clamping', () {
    test('absolute values clamp to registry ranges', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': P.exposure, 'value': 9, 'reason': 'x'},
            {'param': P.contrast, 'value': -400, 'reason': 'x'},
            {'param': 'grade.shadows.hue', 'value': 400, 'reason': 'x'},
          ],
        ),
      ).clampedAbsolute();
      final values = {
        for (final a in r.variants.single.adjustments) a.param: a.value,
      };
      expect(values[P.exposure], 5);
      expect(values[P.contrast], -100);
      expect(values['grade.shadows.hue'], 359);
    });

    test('targets and confidence are clamped too', () {
      final json = _sample();
      final v = (json['variants']! as List).single as Map;
      v['confidence'] = 7;
      (v['targets']! as Map)['midLStar'] = 120;
      (v['targets']! as Map)['wbStrength'] = -3;
      final r = AutoEditResponse.fromJson(json);
      expect(r.variants.single.confidence, 1);
      expect(r.variants.single.targets.midLStar, 100);
      expect(r.variants.single.targets.wbStrength, 0);
    });

    test('deltas clamp so current + delta stays in range', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': P.shadows, 'value': 50, 'reason': 'x'},
            {'param': P.exposure, 'value': -9, 'reason': 'x'},
            {'param': P.temp, 'value': 10, 'reason': 'x'},
          ],
        ),
      ).clampedDeltas({P.shadows: 80, P.exposure: -4});
      final values = {
        for (final a in r.variants.single.adjustments) a.param: a.value,
      };
      expect(values[P.shadows], 20);
      expect(values[P.exposure], closeTo(-1, 1e-9));
      expect(values[P.temp], 10);
    });

    test('withoutParams removes locked params', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': P.shadows, 'value': 10, 'reason': 'x'},
            {'param': P.temp, 'value': 10, 'reason': 'x'},
          ],
        ),
      ).withoutParams({P.temp});
      expect(r.variants.single.adjustments.map((a) => a.param), [P.shadows]);
    });
  });

  group('damping', () {
    test('local-contrast and color params damp at 0.85', () {
      expect(AiDamping.factorFor(P.clarity), 0.85);
      expect(AiDamping.factorFor(P.saturation), 0.85);
      expect(AiDamping.factorFor('hsl.blue.sat'), 0.85);
      expect(AiDamping.factorFor(P.exposure), 1.0);
    });

    test('damps toward the default for absolute values', () {
      expect(AiDamping.damp(P.clarity, 40), closeTo(34, 1e-9));
      expect(
        AiDamping.damp(
          P.vignetteMidpoint,
          50,
          factors: {P.vignetteMidpoint: 0.5},
        ),
        50,
      );
      expect(AiDamping.damp(P.exposure, 0.8), 0.8);
    });

    test('damps toward an explicit origin', () {
      expect(AiDamping.damp(P.clarity, 40, from: 20), closeTo(37, 1e-9));
    });

    test('damped() applies to every adjustment and stays in range', () {
      final r = AutoEditResponse.fromJson(
        _sample(
          adjustments: [
            {'param': P.vibrance, 'value': 100, 'reason': 'x'},
          ],
        ),
      ).damped();
      expect(r.variants.single.adjustments.single.value, closeTo(85, 1e-9));
    });
  });

  test('toJson round-trips', () {
    final r = AutoEditResponse.fromJson(_sample());
    final again = AutoEditResponse.fromJson(r.toJson());
    expect(again.toJson(), r.toJson());
  });

  test('adjustment map helper', () {
    final v = AutoEditResponse.fromJson(_sample()).variants.single;
    expect(v.valuesByParam, {P.shadows: 28.0});
  });
}
