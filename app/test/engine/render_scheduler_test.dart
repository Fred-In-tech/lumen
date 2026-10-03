import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/render_scheduler.dart';
import 'package:lumen_core/lumen_core.dart';

class FakeRenderer implements FrameRenderer {
  FakeRenderer({this.latency = Duration.zero, this.failOn});

  final Duration latency;
  final bool Function(DevelopSettings)? failOn;
  final calls = <({DevelopSettings settings, double scale, bool clip})>[];
  bool disposed = false;

  @override
  Future<ui.Image> render(
    DevelopSettings settings, {
    double scale = 1,
    bool showClipping = false,
  }) async {
    calls.add((settings: settings, scale: scale, clip: showClipping));
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failOn?.call(settings) ?? false) throw StateError('boom');
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final pic = rec.endRecording();
    final img = pic.toImageSync(1, 1);
    pic.dispose();
    return EngineImages.track(img);
  }

  @override
  void dispose() => disposed = true;
}

DevelopSettings _ev(double v) =>
    DevelopSettings.defaults.withValue(P.exposure, v);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('100 rapid updates coalesce into <= 3 renders, last settings win', () {
    fakeAsync((async) {
      final r = FakeRenderer();
      final s = RenderScheduler(r);
      for (var i = 1; i <= 100; i++) {
        s.update(_ev(i / 100));
      }
      async.elapse(const Duration(milliseconds: 50));
      expect(r.calls.length, lessThanOrEqualTo(3));
      expect(r.calls.last.settings, _ev(1));
      expect(s.settings, _ev(1));
      expect(s.frame.value, isNotNull);
      s.dispose();
      expect(r.disposed, isTrue);
      expect(EngineImages.live, 0);
    });
  });

  test('one render in flight; updates during it collapse into one more', () {
    fakeAsync((async) {
      final r = FakeRenderer(latency: const Duration(milliseconds: 10));
      final s = RenderScheduler(r);
      s.update(_ev(0.1));
      async.elapse(const Duration(milliseconds: 2));
      for (var i = 0; i < 50; i++) {
        s.update(_ev(0.2 + i / 100));
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(r.calls.length, 2);
      expect(r.calls.last.settings, _ev(0.69));
      expect(s.generation, 2);
      s.dispose();
      expect(EngineImages.live, 0);
    });
  });

  test(
    'interactive drag renders at 0.5x, then 1x 120 ms after the last change',
    () {
      fakeAsync((async) {
        final r = FakeRenderer();
        final s = RenderScheduler(r);
        s.update(_ev(0.3), interactive: true);
        async.elapse(const Duration(milliseconds: 10));
        expect(r.calls.single.scale, 0.5);
        s.update(_ev(0.4), interactive: true);
        async.elapse(const Duration(milliseconds: 100));
        expect(r.calls.length, 2);
        expect(r.calls.last.scale, 0.5);
        async.elapse(const Duration(milliseconds: 40));
        expect(r.calls.length, 3);
        expect(r.calls.last.scale, 1);
        expect(r.calls.last.settings, _ev(0.4));
        async.elapse(const Duration(seconds: 1));
        expect(r.calls.length, 3);
        s.dispose();
        expect(EngineImages.live, 0);
      });
    },
  );

  test('a committed (non-interactive) update cancels the settle render', () {
    fakeAsync((async) {
      final r = FakeRenderer();
      final s = RenderScheduler(r);
      s.update(_ev(0.3), interactive: true);
      async.elapse(const Duration(milliseconds: 10));
      s.update(_ev(0.3));
      async.elapse(const Duration(seconds: 1));
      expect(r.calls.map((c) => c.scale), [0.5, 1]);
      s.dispose();
    });
  });

  test('render errors are reported and the last good frame stays', () {
    fakeAsync((async) {
      final r = FakeRenderer(failOn: (s) => s.value(P.exposure) > 1);
      final s = RenderScheduler(r);
      final errors = <Object>[];
      s.errors.listen(errors.add);
      s.update(_ev(0.5));
      async.elapse(const Duration(milliseconds: 10));
      final good = s.frame.value;
      s.update(_ev(2));
      async.elapse(const Duration(milliseconds: 10));
      expect(errors, hasLength(1));
      expect(s.frame.value, same(good));
      expect(s.settings, _ev(0.5));
      s.dispose();
      expect(EngineImages.live, 0);
    });
  });

  test('showClipping re-renders with the overlay flag', () {
    fakeAsync((async) {
      final r = FakeRenderer();
      final s = RenderScheduler(r);
      s.update(_ev(0));
      async.elapse(const Duration(milliseconds: 10));
      s.showClipping = true;
      async.elapse(const Duration(milliseconds: 10));
      expect(r.calls.map((c) => c.clip), [false, true]);
      s.dispose();
    });
  });

  test(
    'idle() completes once all work is done; frames after dispose are released',
    () {
      fakeAsync((async) {
        final r = FakeRenderer(latency: const Duration(milliseconds: 5));
        final s = RenderScheduler(r);
        var idle = false;
        s.update(_ev(0.1));
        s.idle().then((_) => idle = true);
        async.elapse(const Duration(milliseconds: 2));
        expect(idle, isFalse);
        async.elapse(const Duration(milliseconds: 10));
        expect(idle, isTrue);
        s.update(_ev(0.2));
        async.elapse(const Duration(milliseconds: 1));
        s.dispose(); // render still in flight
        async.elapse(const Duration(milliseconds: 20));
        expect(EngineImages.live, 0);
      });
    },
  );
}
