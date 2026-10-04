import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen_core/lumen_core.dart';

/// A [w]×[h] op on a 100×80 source with a solid red patch.
HealOp _op(String id, PixelBox box, {bool hidden = false}) => HealOp.forPatch(
  id: id,
  bbox: box,
  srcWidth: 100,
  srcHeight: 80,
  engine: 'pushpull@1',
  ai: false,
  strokes: const [],
).copyWith(hidden: hidden);

RgbaBuffer _red(PixelBox box) =>
    RgbaBuffer.filled(box.width, box.height, 255, 0, 0);

void main() {
  late MemoryPatchStore store;
  late List<String> loads;
  late HealedSourceCache cache;

  const small = PixelBox(10, 10, 4, 4); // 0.2 % of the frame
  const big = PixelBox(40, 20, 40, 40); // 20 %

  setUp(() async {
    store = MemoryPatchStore();
    await store.save('a', 'retouch/s.png', _red(small));
    await store.save('a', 'retouch/b.png', _red(big));
    loads = [];
    cache = HealedSourceCache((ref) {
      loads.add(ref);
      return store.load('a', ref);
    });
  });

  RgbaBuffer grey(int w, int h) => RgbaBuffer.filled(w, h, 90, 90, 90);

  test('no visible ops: the preview itself, nothing loaded', () async {
    final preview = grey(100, 80);
    for (final ops in [
      <HealOp>[],
      [_op('s', small, hidden: true)],
    ]) {
      final r = await cache.compose(preview, ops);
      expect(identical(r.buffer, preview), isTrue);
      expect(r.healed, isFalse);
      expect(r.needsAuxRecompute, isFalse);
    }
    expect(loads, isEmpty);
  });

  test('hit on the same preview and heal list; miss when either '
      'changes', () async {
    final preview = grey(100, 80);
    final ops = [_op('s', small)];
    expect(cache.peek(preview, ops), isNull);
    final first = await cache.compose(preview, ops);
    expect(first.healed, isTrue);
    expect(first.needsAuxRecompute, isFalse);
    final o = first.buffer.offset(11, 11);
    expect(first.buffer.data.sublist(o, o + 3), [255, 0, 0]);
    expect(preview.data.sublist(o, o + 3), [90, 90, 90], reason: 'copy');

    // Same list, and an equal list rebuilt from JSON (undo/redo): hits.
    expect(identical(await cache.compose(preview, ops), first), isTrue);
    final roundTrip = parseHealOps([for (final op in ops) op.toJson()]);
    expect(identical(cache.peek(preview, roundTrip), first), isTrue);
    expect(loads, ['retouch/s.png']);

    // A new op: miss; only its patch is loaded.
    final more = [...ops, _op('b', big)];
    final second = await cache.compose(preview, more);
    expect(identical(second, first), isFalse);
    expect(second.needsAuxRecompute, isTrue);
    expect(loads, ['retouch/s.png', 'retouch/b.png']);

    // Another preview buffer of the same size: miss.
    expect(cache.peek(grey(100, 80), more), isNull);
  });

  test('each preview size is cached on its own and scales the boxes', () async {
    final full = grey(100, 80), half = grey(50, 40);
    final ops = [_op('b', big)];
    final a = await cache.compose(full, ops);
    final b = await cache.compose(half, ops);
    expect(identical(cache.peek(full, ops), a), isTrue);
    expect(identical(cache.peek(half, ops), b), isTrue);
    // big covers x 40..79, y 20..59 at full size → 20..39, 10..29 at half.
    final inside = b.buffer.offset(30, 20), outside = b.buffer.offset(10, 20);
    expect(b.buffer.data.sublist(inside, inside + 3), [255, 0, 0]);
    expect(b.buffer.data.sublist(outside, outside + 3), [90, 90, 90]);
    expect(loads, ['retouch/b.png'], reason: 'patch decoded once');
  });

  test('one-off composes reuse patches and keep the preview entries', () async {
    final preview = grey(100, 80);
    final ops = [_op('b', big)];
    final kept = await cache.compose(preview, ops);
    for (var i = 1; i <= 4; i++) {
      final thumb = await cache.composeOnce(grey(10 * i, 8 * i), ops);
      expect(thumb.healed, isTrue);
    }
    expect(identical(cache.peek(preview, ops), kept), isTrue);
    expect(loads, ['retouch/b.png']);
  });

  test('missing patches are skipped', () async {
    final preview = grey(100, 80);
    final r = await cache.compose(preview, [_op('gone', small)]);
    expect(r.healed, isFalse);
    expect(identical(r.buffer, preview), isTrue);
  });

  test('full-resolution compose is exact', () async {
    final src = grey(100, 80);
    final out = await composeHealedFullRes(store, 'a', src, [_op('b', big)]);
    final o = out.offset(40, 20);
    expect(out.data.sublist(o, o + 3), [255, 0, 0]);
    expect(out.data.sublist(out.offset(39, 20), out.offset(39, 20) + 3), [
      90,
      90,
      90,
    ]);
    expect(
      identical(await composeHealedFullRes(store, 'a', src, []), src),
      isTrue,
    );
  });
}
