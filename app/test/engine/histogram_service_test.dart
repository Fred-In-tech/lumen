import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/histogram_service.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';

ui.Image _tiny() {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
  final pic = rec.endRecording();
  final img = pic.toImageSync(1, 1);
  pic.dispose();
  return img;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('known 4-color image gives exact bins and clip counts', () async {
    final b = RgbaBuffer(64, 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final q = (x ~/ 32) + 2 * (y ~/ 32);
        final (r, g, bb) = [
          (255, 0, 0),
          (0, 255, 0),
          (0, 0, 0),
          (40, 80, 120),
        ][q];
        b.setPixel(x, y, r, g, bb);
      }
    }
    final img = await imageFromBuffer(b);
    final h = await HistogramService.measure(img);
    expect(h.pixelCount, 4096);
    expect(h.red[255], 1024);
    expect(h.red[0], 2048);
    expect(h.red[40], 1024);
    expect(h.green[255], 1024);
    expect(h.blue[120], 1024);
    expect(h.highClipped, 2048);
    expect(h.lowClipped, 1024);
    expect(h.showHighClipWarning, isTrue);
    EngineImages.dispose(img);
  });

  test('large frames are measured from a <= 256 px wide downscale', () async {
    final img = await imageFromBuffer(RgbaBuffer.filled(1024, 512, 90, 90, 90));
    final h = await HistogramService.measure(img);
    expect(h.pixelCount, 256 * 128);
    expect(h.red[90], h.pixelCount);
    EngineImages.dispose(img);
  });

  test('throttles to one measurement per interval, latest frame wins', () {
    fakeAsync((async) {
      final measured = <int>[];
      var n = 0;
      final svc = HistogramService(
        measure: (img) async {
          measured.add(n);
          return Histogram.compute(RgbaBuffer.filled(1, 1, 0, 0, 0));
        },
      );
      final got = <Histogram>[];
      svc.histograms.listen(got.add);
      for (n = 0; n < 30; n++) {
        final f = _tiny();
        svc.submit(f);
        f.dispose();
        async.elapse(const Duration(milliseconds: 10)); // 100 Hz input
      }
      async.elapse(const Duration(milliseconds: 300));
      // 300 ms of 100 Hz input at a 10 Hz throttle: leading + ~3 + trailing.
      expect(measured.length, inInclusiveRange(3, 5));
      expect(measured.first, 0);
      expect(measured.last, 29);
      expect(got.length, measured.length);
      expect(svc.latest, isNotNull);
      svc.dispose();
    });
  });

  test('errors are forwarded and the service keeps running', () {
    fakeAsync((async) {
      var calls = 0;
      final svc = HistogramService(
        measure: (img) async {
          calls++;
          if (calls == 1) throw StateError('readback failed');
          return Histogram.compute(RgbaBuffer.filled(1, 1, 0, 0, 0));
        },
      );
      final errors = <Object>[];
      final ok = <Histogram>[];
      svc.histograms.listen(ok.add, onError: errors.add);
      for (var i = 0; i < 2; i++) {
        final f = _tiny();
        svc.submit(f);
        f.dispose();
        async.elapse(const Duration(milliseconds: 150));
      }
      expect(errors, hasLength(1));
      expect(ok, hasLength(1));
      svc.dispose();
    });
  });
}
