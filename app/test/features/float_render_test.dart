import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/features/editor/renderer/gpu_float_export.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

/// The float path in the editor's renderer and the export service
/// (docs/HIGH_BIT_DEPTH.md). The probe is forced on, so the wiring also
/// runs under the default headless renderer: a float source is uploaded
/// and develop samples it directly there too (only passes between source
/// and develop would be 8-bit). The engine suites cover real float targets.

const _w = 320, _h = 240;

/// Rows ramp from mid grey to 4x display white (encoded).
FloatBuffer _hot() {
  final top = linearToSrgbExtended(4);
  final b = FloatBuffer(_w, _h);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      final v = 0.5 + (top - 0.5) * x / (_w - 1);
      b.setPixel(x, y, v, v, v);
    }
  }
  return b;
}

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

class _Source extends MemoryFloatSource {
  _Source(super.pixels, {this.failing = false})
    : super(profile: HbdProfile.rawExtended);

  final bool failing;
  int released = 0;

  @override
  Future<FloatPixels> render({
    required int fullWidth,
    required int fullHeight,
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  }) {
    if (failing) throw const FloatSourceException('decode failed');
    return super.render(
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  @override
  Future<void> release() async => released++;
}

Future<RgbaBuffer> _frame(
  GpuPhotoRenderer r,
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

/// Distinct levels in the right half of the middle row (above white in the
/// source).
int _topLevels(RgbaBuffer b, [int row = _h ~/ 2]) =>
    {for (var x = b.width ~/ 2; x < b.width; x++) b.g(x, row * b.height ~/ _h)}
        .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hot = _hot();
  final rendition = _png(hot.toRgba());
  final darker = DevelopSettings.defaults.withValue(P.exposure, -2);

  setUp(() => HbdCapability.override = true);
  tearDown(HbdCapability.reset);

  group('GpuPhotoRenderer', () {
    test('develops the float source: highlights the 8-bit rendition clips '
        'come back', () async {
      final source = _Source(hot);
      final onFloat = GpuPhotoRenderer(
        assetId: 'a',
        floatSource: (id) async => source,
      );
      final onBytes = GpuPhotoRenderer(assetId: 'a');
      await onFloat.open(rendition);
      await onBytes.open(rendition);
      expect(onFloat.usingFloat, isTrue);
      expect(onBytes.usingFloat, isFalse);
      // `before` and the analysis proxy stay the 8-bit rendition.
      expect(onFloat.before!.width, _w);
      expect(onFloat.analysisProxy, isNotNull);
      final f = await _frame(onFloat, darker);
      final b = await _frame(onBytes, darker);
      expect((f.width, f.height), (_w, _h));
      expect(_topLevels(b), 1);
      expect(_topLevels(f), greaterThan(40));
      // Thumbnails come from the same graph.
      final thumb = img.decodePng(await onFloat.renderThumbnail(darker))!;
      expect(thumb.width, _w);
      onFloat.dispose();
      onBytes.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(source.released, 1);
    });

    test('keeps the 8-bit path when the device fails the probe', () async {
      HbdCapability.override = false;
      var asked = 0;
      final r = GpuPhotoRenderer(
        assetId: 'a',
        floatSource: (id) async {
          asked++;
          return _Source(hot);
        },
      );
      await r.open(rendition);
      expect(r.usingFloat, isFalse);
      expect(asked, 0);
      expect(_topLevels(await _frame(r, darker)), 1);
      r.dispose();
    });

    test('keeps the 8-bit path without a source, when the decode fails or '
        'the source is another picture', () async {
      for (final loader in <FloatSourceLoader>[
        (id) async => null,
        (id) async => _Source(hot, failing: true),
        (id) async => _Source(FloatBuffer(100, 300)),
      ]) {
        final r = GpuPhotoRenderer(assetId: 'a', floatSource: loader);
        await r.open(rendition);
        expect(r.usingFloat, isFalse);
        expect(_topLevels(await _frame(r, darker)), 1);
        r.dispose();
      }
    });

    test('heal patches are drawn over the float source', () async {
      const box = PixelBox(40, 60, 60, 40);
      final store = MemoryPatchStore();
      await store.save(
        'a',
        'retouch/h.png',
        RgbaBuffer.filled(box.width, box.height, 230, 20, 40),
      );
      final r = GpuPhotoRenderer(
        assetId: 'a',
        floatSource: (id) async => _Source(hot),
      )..setHealer(HealedSourceCache((ref) => store.load('a', ref)));
      await r.open(rendition);
      expect(r.usingFloat, isTrue);
      final op = HealOp.forPatch(
        id: 'h',
        bbox: box,
        srcWidth: _w,
        srcHeight: _h,
        engine: 'patchmatch@1',
        ai: false,
        strokes: const [],
      );
      bool red(RgbaBuffer b) => b.r(70, 80) > 200 && b.g(70, 80) < 60;
      final healed = await _frame(
        r,
        DevelopSettings.defaults.copyWith(heal: [op]),
        done: red,
      );
      expect(red(healed), isTrue);
      // Outside the patch the photo is unchanged...
      expect(healed.g(0, 200), closeTo(128, 2));
      // ...and without the op the patch is gone again.
      final plain = await _frame(
        r,
        DevelopSettings.defaults,
        done: (b) => !red(b),
      );
      expect(red(plain), isFalse);
      r.dispose();
    });
  });

  group('HealedSourceCache.overlay', () {
    test('premultiplied patches only; null when nothing draws', () async {
      final store = MemoryPatchStore();
      await store.save(
        'a',
        'retouch/h.png',
        RgbaBuffer.filled(8, 8, 200, 100, 50),
      );
      final cache = HealedSourceCache((ref) => store.load('a', ref));
      final op = HealOp.forPatch(
        id: 'h',
        bbox: const PixelBox(4, 4, 8, 8),
        srcWidth: 32,
        srcHeight: 32,
        engine: 'patchmatch@1',
        ai: false,
        strokes: const [],
      );
      final overlay = (await cache.overlay(32, 32, [op]))!;
      final inside = overlay.offset(8, 8), outside = overlay.offset(20, 20);
      expect(overlay.data.sublist(inside, inside + 4), [200, 100, 50, 255]);
      expect(overlay.data.sublist(outside, outside + 4), [0, 0, 0, 0]);
      expect(await cache.overlay(32, 32, const []), isNull);
      expect(await cache.overlay(32, 32, [op.copyWith(hidden: true)]), isNull);
    });
  });

  group('export', () {
    Future<(MemoryCatalogRepository, String)> photo() async {
      final repo = MemoryCatalogRepository();
      final r = await ImportService(repo)
          .importOne(ImportFile(name: 'hot.png', bytes: rendition));
      return (repo, (r as Imported).entry.assetId);
    }

    RgbaBuffer decode(Uint8List png) {
      final d = img.decodePng(png)!;
      final out = RgbaBuffer(d.width, d.height);
      for (var y = 0; y < d.height; y++) {
        for (var x = 0; x < d.width; x++) {
          final p = d.getPixel(x, y);
          out.setPixel(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt());
        }
      }
      return out;
    }

    const png = ExportOptions(format: ExportFormat.png);

    test(
      'photos with a float source export from it, window by window',
      () async {
        final (repo, id) = await photo();
        await repo.saveEdit(EditDocument.create(id).copyWith(settings: darker));
        final source = _Source(hot);
        lastFloatExportStats = null;
        final float = await ExportService(
          repo,
          floatExport: gpuFloatExport((_) async => source),
        ).exportOne(id, png);
        final bytes = await ExportService(repo).exportOne(id, png);
        expect((float.width, float.height), (_w, _h));
        expect(_topLevels(decode(bytes.bytes)), 1);
        expect(_topLevels(decode(float.bytes)), greaterThan(40));
        final stats = lastFloatExportStats!;
        expect((stats.sourceWidth, stats.sourceHeight), (_w, _h));
        expect(stats.tiles, 1);
        // One analysis-size decode for the aux maps, one window per tile.
        expect(source.renders, 2);
        await Future<void>.delayed(Duration.zero);
        expect(source.released, 1);
        expect(EngineImages.live, 0);
      },
    );

    test('a long-edge export and heal patches', () async {
      final (repo, id) = await photo();
      const box = PixelBox(40, 60, 60, 40);
      final store = MemoryPatchStore();
      await store.save(
        id,
        'retouch/h.png',
        RgbaBuffer.filled(box.width, box.height, 230, 20, 40),
      );
      final op = HealOp.forPatch(
        id: 'h',
        bbox: box,
        srcWidth: _w,
        srcHeight: _h,
        engine: 'patchmatch@1',
        ai: false,
        strokes: const [],
      );
      await repo.saveEdit(
        EditDocument.create(id)
            .copyWith(settings: DevelopSettings.defaults.copyWith(heal: [op])),
      );
      final out =
          await ExportService(
            repo,
            patches: () async => store,
            floatExport: gpuFloatExport((_) async => _Source(hot)),
          ).exportOne(
            id,
            const ExportOptions(format: ExportFormat.png, longEdge: 160),
          );
      expect((out.width, out.height), (160, 120));
      final d = decode(out.bytes);
      expect(d.r(35, 40), greaterThan(200));
      expect(d.g(35, 40), lessThan(60));
      expect(d.g(0, 100), closeTo(129, 3));
      expect(lastFloatExportStats!.sourceWidth, 160);
    });

    test('no float source, a failed probe or a failing decoder: the 8-bit '
        'export, never an error', () async {
      final (repo, id) = await photo();
      await repo.saveEdit(EditDocument.create(id).copyWith(settings: darker));
      final reference = (await ExportService(repo).exportOne(id, png)).bytes;
      for (final loader in <FloatSourceLoader>[
        (_) async => null,
        (_) async => _Source(hot, failing: true),
      ]) {
        final out = await ExportService(
          repo,
          floatExport: gpuFloatExport(loader),
        ).exportOne(id, png);
        expect(out.bytes, reference);
      }
      HbdCapability.override = false;
      final out = await ExportService(
        repo,
        floatExport: gpuFloatExport((_) async => _Source(hot)),
      ).exportOne(id, png);
      expect(out.bytes, reference);
    });
  });
}
