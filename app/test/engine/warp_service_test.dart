import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/warp_service.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/warp/support/warp_faces.dart';

const _w = 400, _h = 300;
final _faces = synthAnalysis(_w, _h, [face('a', 200, 120, 60)]);

DevelopSettings _shape(double v) => DevelopSettings.defaults.copyWith(
  portrait: shapes({PortraitIds.faceWidth: v}),
);

LiquifyStroke _stroke(int points, {double y = 0.5}) => LiquifyStroke(
  tool: LiquifyTool.push,
  points: [for (var i = 0; i < points; i++) (0.3 + i * 0.02, y)],
  radius: 0.06,
  strength: 0.8,
);

WarpField _replay(DevelopSettings s) => buildWarpField(
  WarpRequest.fromSettings(s, _faces, sourceWidth: _w, sourceHeight: _h),
);

void main() {
  late List<WarpField?> published;
  late int builds;
  late WarpFieldService svc;

  WarpFieldService make() => WarpFieldService(
    sourceWidth: _w,
    sourceHeight: _h,
    onField: published.add,
    build: (r) async {
      builds++;
      return buildWarpWithPrefix(r);
    },
  )..faces = _faces;

  setUp(() {
    published = [];
    builds = 0;
  });

  test(
    'shape drags are debounced (80 ms) and keep the old field meanwhile',
    () {
      fakeAsync((async) {
        svc = make();
        svc.update(_shape(20));
        async.elapse(const Duration(milliseconds: 100));
        expect(builds, 1);
        expect(published.length, 1);
        final first = published.last;
        for (var v = 30.0; v <= 90; v += 10) {
          svc.update(_shape(v));
          async.elapse(const Duration(milliseconds: 20));
        }
        expect(published.last, same(first)); // old field still shown
        async.elapse(const Duration(milliseconds: 100));
        expect(builds, 2);
        expect(published.last!.packRgba(), _replay(_shape(90)).packRgba());
        svc.dispose();
      });
    },
  );

  test('a growing live stroke updates synchronously, no rebuild', () {
    fakeAsync((async) {
      svc = make();
      var s = _shape(50).copyWith(liquify: [_stroke(2)]);
      svc.update(s);
      async.elapse(const Duration(milliseconds: 100));
      expect(builds, 1);
      for (var n = 3; n <= 8; n++) {
        s = s.copyWith(liquify: [_stroke(n)]);
        svc.update(s);
        expect(published.last!.packRgba(), _replay(s).packRgba());
      }
      // A second stroke starts: the first becomes part of the prefix.
      s = s.copyWith(liquify: [_stroke(8), _stroke(3, y: 0.7)]);
      svc.update(s);
      expect(published.last!.packRgba(), _replay(s).packRgba());
      expect(builds, 1);
      // Undo of the last stroke is synchronous too.
      s = s.copyWith(liquify: [_stroke(8)]);
      svc.update(s);
      expect(published.last!.packRgba(), _replay(s).packRgba());
      expect(builds, 1);
      svc.dispose();
    });
  });

  test('editing an earlier stroke rebuilds at once (no debounce)', () {
    fakeAsync((async) {
      svc = make();
      svc.update(
        DevelopSettings.defaults.copyWith(
          liquify: [_stroke(4), _stroke(4, y: 0.7)],
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
      final s = DevelopSettings.defaults.copyWith(
        liquify: [_stroke(4, y: 0.7)],
      );
      svc.update(s);
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(builds, 2);
      expect(published.last!.packRgba(), _replay(s).packRgba());
      svc.dispose();
    });
  });

  test('no warp edits publish null; new faces rebuild', () {
    fakeAsync((async) {
      svc = make();
      svc.update(_shape(40));
      async.elapse(const Duration(milliseconds: 100));
      expect(published.last, isNotNull);
      svc.update(DevelopSettings.defaults);
      expect(published.last, isNull);
      svc.update(_shape(40));
      async.elapse(const Duration(milliseconds: 100));
      final before = builds;
      svc.faces = synthAnalysis(_w, _h, [face('b', 150, 120, 50)]);
      async.elapse(const Duration(milliseconds: 100));
      expect(builds, before + 1);
      svc.faces = null; // shape sliders need faces
      expect(published.last, isNull);
      svc.dispose();
    });
  });

  test('fieldFor returns the exact field for other settings', () async {
    svc = make();
    final s = _shape(60).copyWith(liquify: [_stroke(5)]);
    expect((await svc.fieldFor(s)).packRgba(), _replay(s).packRgba());
    expect((await svc.fieldFor(DevelopSettings.defaults)).isIdentity, isTrue);
    svc.dispose();
  });
}
