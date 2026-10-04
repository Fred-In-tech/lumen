import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/test_images.dart';

const _w = 320, _h = 240;

/// The heal op's box in source (= preview) pixels.
const _small = PixelBox(100, 80, 40, 30);

/// A box over 20 % of the frame (the aux maps must be rebuilt).
const _big = PixelBox(40, 40, 200, 150);

Uint8List _png(RgbaBuffer b) => Uint8List.fromList(
  img.encodePng(
    img.Image.fromBytes(
      width: b.width,
      height: b.height,
      bytes: b.data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
  ),
);

HealOp _op(String id, PixelBox box) => HealOp.forPatch(
  id: id,
  bbox: box,
  srcWidth: _w,
  srcHeight: _h,
  engine: 'patchmatch@1',
  ai: false,
  strokes: const [],
);

Future<HealedSourceCache> _healer() async {
  final store = MemoryPatchStore();
  for (final (id, box) in [('s', _small), ('b', _big)]) {
    await store.save(
      'a',
      'retouch/$id.png',
      RgbaBuffer.filled(box.width, box.height, 230, 20, 40),
    );
  }
  return HealedSourceCache((ref) => store.load('a', ref));
}

/// Renders [s] and waits for a new frame that satisfies [done] (the GPU
/// renderer swaps the healed source in asynchronously, so the first frame
/// after an update may still show the previous heals).
Future<RgbaBuffer> _frame(
  PhotoRenderer r,
  DevelopSettings s, {
  bool Function(RgbaBuffer frame)? done,
}) async {
  var previous = r.output.value;
  r.update(s);
  RgbaBuffer? last;
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final out = r.output.value;
    if (out == null || identical(out, previous)) continue;
    previous = out;
    last = await rgbaFromImage(out);
    if (done == null || done(last)) return last;
  }
  if (last != null) return last;
  throw StateError('no frame');
}

/// The patch colour (230, 20, 40) at ([x], [y]); the scene never has it.
bool _redAt(RgbaBuffer b, int x, int y) {
  final o = b.offset(x, y);
  return b.data[o] > 200 && b.data[o + 1] < 60;
}

/// Pixels that differ (any channel by more than [tol]), split by [box].
({int inside, int outside}) _diff(
  RgbaBuffer a,
  RgbaBuffer b,
  PixelBox box, {
  int tol = 0,
}) {
  var inside = 0, outside = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final o = a.offset(x, y);
      var d = 0;
      for (var c = 0; c < 3; c++) {
        d = d > (a.data[o + c] - b.data[o + c]).abs()
            ? d
            : (a.data[o + c] - b.data[o + c]).abs();
      }
      if (d <= tol) continue;
      final inBox = x >= box.x && x < box.right && y >= box.y && y < box.bottom;
      inBox ? inside++ : outside++;
    }
  }
  return (inside: inside, outside: outside);
}

Future<void> _checkRenderer(PhotoRenderer r, {required int tol}) async {
  final scene = TestScenes.portrait(_w, _h);
  await r.open(_png(scene));
  (r as HealSink).setHealer(await _healer());
  final plain = await _frame(r, DevelopSettings.defaults);

  final healed = await _frame(
    r,
    DevelopSettings.defaults.copyWith(heal: [_op('s', _small)]),
    done: (f) => _redAt(f, _small.x + 20, _small.y + 15),
  );
  final d = _diff(plain, healed, _small, tol: tol);
  expect(d.inside, greaterThan(_small.area * 0.9));
  expect(d.outside, 0, reason: 'only the patch changes');
  expect(_redAt(healed, _small.x + 20, _small.y + 15), isTrue);

  // "Before" is the unhealed source, and so is a render without heals.
  final before = await rgbaFromImage(r.before!);
  expect(_diff(before, scene, _small, tol: tol).inside, 0);
  final back = await _frame(
    r,
    DevelopSettings.defaults,
    done: (f) => !_redAt(f, _small.x + 20, _small.y + 15),
  );
  expect(_diff(plain, back, _small, tol: tol).inside, 0);

  // A large heal (aux maps rebuilt) still only changes its own box.
  final big = await _frame(
    r,
    DevelopSettings.defaults.copyWith(heal: [_op('b', _big)]),
    done: (f) => _redAt(f, _big.x + 100, _big.y + 75),
  );
  final db = _diff(plain, big, _big, tol: tol);
  expect(db.inside, greaterThan(_big.area * 0.9));
  expect(db.outside, 0);

  // Thumbnails draw the heals too.
  final png = await r.renderThumbnail(
    DevelopSettings.defaults.copyWith(heal: [_op('b', _big)]),
    longEdge: 160,
  );
  final thumb = img.decodePng(png)!;
  final p = thumb.getPixel(70, 57);
  expect(p.r, greaterThan(200));
  expect(p.g, lessThan(60));
}

void main() {
  testWidgets('CPU preview: a heal op changes only its patch; before is '
      'unhealed', (tester) async {
    await tester.runAsync(() async {
      final r = CpuPhotoRenderer(previewLongEdge: _w, interactiveLongEdge: _w);
      addTearDown(r.dispose);
      await _checkRenderer(r, tol: 0);
    });
  });

  testWidgets('GPU preview: the healed source is swapped in, before is '
      'unhealed', (tester) async {
    await tester.runAsync(() async {
      final r = GpuPhotoRenderer(assetId: 'a', previewLongEdge: _w);
      addTearDown(r.dispose);
      await _checkRenderer(r, tol: 1);
      expect(r.usingFallback, isFalse);
    });
  });

  test('a renderer without a healer ignores heal ops', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final r = CpuPhotoRenderer(previewLongEdge: _w, interactiveLongEdge: _w);
    addTearDown(r.dispose);
    await r.open(_png(TestScenes.portrait(_w, _h)));
    final plain = await _frame(r, DevelopSettings.defaults);
    final withOps = await _frame(
      r,
      DevelopSettings.defaults.copyWith(heal: [_op('s', _small)]),
    );
    expect(withOps.data, plain.data);
  });
}
