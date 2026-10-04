import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('localAllowed registry flags', () {
    test('exactly the 12 local params are allowed', () {
      final allowed = ParamRegistry.all
          .where((p) => p.localAllowed)
          .map((p) => p.id)
          .toSet();
      expect(allowed, {
        P.exposure,
        P.contrast,
        P.highlights,
        P.shadows,
        P.whites,
        P.blacks,
        P.temp,
        P.tint,
        P.saturation,
        P.texture,
        P.clarity,
        P.dehaze,
      });
      expect(kLocalParams.toSet(), allowed);
      expect(kLocalParams, hasLength(12));
    });
  });

  group('LocalMask JSON', () {
    test('v1 JSON without strokes still parses (backward compatible)', () {
      final m = LocalMask.fromJson({
        'id': 'm1',
        'name': 'Sky',
        'kind': 'linear',
        'invert': false,
        'opacity': 1,
        'shape': {'x0': 0.5, 'y0': 0.0, 'x1': 0.5, 'y1': 0.6},
        'adjustments': {'exposure': -0.5},
      });
      expect(m.kind, MaskKind.linear);
      expect(m.strokes, isEmpty);
      expect(m.linear.y1, 0.6);
      expect(m.adjustments, {P.exposure: -0.5});
    });

    test('all kinds round-trip, including AI kinds and brush strokes', () {
      for (final kind in MaskKind.values.where(
        (k) => k != MaskKind.unsupported,
      )) {
        final m = LocalMask(
          id: 'id-${kind.name}',
          name: kind.name,
          kind: kind,
          invert: true,
          opacity: 0.7,
          shape: kind.isAi
              ? const {
                  'maskRef': 'masks/m1.png',
                  'model': 'u2net',
                  'modelVersion': '1',
                }
              : const {'cx': 0.4, 'cy': 0.5, 'rx': 0.2, 'ry': 0.3},
          strokes: const [
            BrushStroke(
              points: [(0.1, 0.2), (0.3, 0.4)],
              radius: 0.05,
              hardness: 0.5,
              flow: 0.8,
            ),
            BrushStroke(points: [(0.2, 0.2)], radius: 0.02, erase: true),
          ],
          adjustments: const {P.exposure: 0.5, P.clarity: -20},
        );
        final back = LocalMask.fromJson(m.toJson());
        expect(back, m, reason: kind.name);
        expect(back.hashCode, m.hashCode);
      }
    });

    test('adjustments keep only localAllowed params, clamped', () {
      final m = LocalMask.fromJson({
        'id': 'a',
        'kind': 'radial',
        'adjustments': {
          'exposure': 9,
          'vibrance': 20,
          'sharpen.amount': 40,
          'hsl.red.sat': 10,
          'clarity': -30,
        },
      });
      expect(m.adjustments, {P.exposure: 5, P.clarity: -30});
    });

    test('opacity clamps', () {
      final m = LocalMask.fromJson({'kind': 'radial', 'opacity': 3});
      expect(m.opacity, 1);
    });
  });

  group('unsupported (newer-version) kinds', () {
    final json = <String, Object?>{
      'id': 'p1',
      'name': 'People',
      'kind': 'people',
      'invert': false,
      'opacity': 0.8,
      'shape': {
        'components': [
          {'op': 'add', 'kind': 'people', 'ref': 'masks/p1_0.png'},
        ],
      },
      'adjustments': {'exposure': 1.0, 'future.param': 3},
      'newField': true,
    };

    test('are kept as unsupported, never as a radial', () {
      final m = LocalMask.fromJson(json);
      expect(m.kind, MaskKind.unsupported);
      expect(m.rawKind, 'people');
      expect(m.isSupported, isFalse);
    });

    test('round-trip their JSON exactly', () {
      final m = LocalMask.fromJson(json);
      expect(m.toJson(), json);
      final back = LocalMask.fromJson(m.toJson());
      expect(back, m);
      final renamed = m.copyWith(name: 'Group');
      expect(renamed.toJson()['name'], 'Group');
      expect(renamed.toJson()['newField'], true);
    });

    test('are inert: no adjustments, no coverage, no uniforms', () {
      final m = LocalMask.fromJson(json);
      expect(m.localAdjustments, isEmpty);
      expect(m.hasAdjustments, isFalse);
      final withStroke = m.copyWith(
        strokes: const [
          BrushStroke(points: [(0.5, 0.5)], radius: 0.3),
        ],
      );
      final c = MaskRasterizer.rasterize(withStroke, 16, 16);
      expect(c.every((v) => v == 0), isTrue);
      final s = DevelopSettings.defaults.copyWith(masks: [m]);
      final f = DevelopUniforms.pack(
        s,
        const DevelopContext(
          outWidth: 4,
          outHeight: 4,
          sourceWidth: 4,
          sourceHeight: 4,
          auxWidth: 1,
          auxHeight: 1,
        ),
      );
      expect(f[DevelopIndex.maskGrid + 2], 0);
      final img = RgbaBuffer.filled(8, 8, 100, 120, 140);
      expect(
        renderReference(img, s).data,
        renderReference(img, DevelopSettings.defaults).data,
      );
    });

    test('a missing kind is unsupported too', () {
      expect(LocalMask.fromJson({'id': 'x'}).kind, MaskKind.unsupported);
    });

    test('survive a DevelopSettings JSON round-trip', () {
      final s = DevelopSettings.defaults.copyWith(
        masks: [LocalMask.fromJson(json)],
      );
      final back = DevelopSettings.fromJson(s.toJson());
      expect(back.masks.single.toJson(), json);
    });
  });

  group('typed shape views', () {
    test('radial defaults and fields', () {
      const m = LocalMask(id: 'r', name: 'R', kind: MaskKind.radial);
      expect(m.radial.cx, 0.5);
      expect(m.radial.feather, 0.5);
      expect(m.radial.inverted, isFalse);
      final r = m.copyWith(
        shape: const RadialShape(
          cx: 0.2,
          cy: 0.3,
          rx: 0.1,
          ry: 0.2,
          angle: 30,
          feather: 0.25,
          inverted: true,
        ).toJson(),
      );
      expect(r.radial.angle, 30);
      expect(r.radial.inverted, isTrue);
    });

    test('ai shape', () {
      const m = LocalMask(
        id: 's',
        name: 'Subject',
        kind: MaskKind.subject,
        shape: {'maskRef': 'masks/s.png', 'model': 'm', 'modelVersion': '2'},
      );
      expect(m.ai.maskRef, 'masks/s.png');
      expect(MaskKind.subject.isAi, isTrue);
      expect(MaskKind.brush.isAi, isFalse);
    });
  });

  group('coverage key', () {
    const base = LocalMask(
      id: 'm',
      name: 'M',
      kind: MaskKind.radial,
      shape: {'cx': 0.5},
      adjustments: {P.exposure: 1},
    );

    test('ignores adjustments and name', () {
      final other = base.copyWith(
        name: 'renamed',
        adjustments: const {P.exposure: -1, P.shadows: 20},
      );
      expect(other.coverageKey, base.coverageKey);
    });

    test('changes with shape, strokes, invert and opacity', () {
      expect(
        base.copyWith(shape: const {'cx': 0.6}).coverageKey,
        isNot(base.coverageKey),
      );
      expect(base.copyWith(invert: true).coverageKey, isNot(base.coverageKey));
      expect(base.copyWith(opacity: 0.5).coverageKey, isNot(base.coverageKey));
      expect(
        base
            .copyWith(
              strokes: const [
                BrushStroke(points: [(0.5, 0.5)], radius: 0.1),
              ],
            )
            .coverageKey,
        isNot(base.coverageKey),
      );
    });

    test('withAdjustment validates the parameter', () {
      final m = base.withAdjustment(P.shadows, 150);
      expect(m.adjustments[P.shadows], 100);
      expect(() => base.withAdjustment(P.vibrance, 10), throwsArgumentError);
      expect(base.withAdjustment(P.exposure, 0).adjustments, isEmpty);
    });
  });
}
