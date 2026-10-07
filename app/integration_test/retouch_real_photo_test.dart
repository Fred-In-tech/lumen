// Retouch on a real photo, on the real app stack (macOS: Metal, LiteRT):
// full-resolution face tiles and segmentation-based skin masks against the
// previous analysis on the downscaled decode. Skipped unless
// LUMEN_RAW_SAMPLE points at a photo the app can read (the macOS app is
// sandboxed: copy it into its container first). The Selfie Multiclass
// model must already be in the app's model store (the test never
// downloads). No photo is stored in the repository.
//
//   flutter test integration_test/retouch_real_photo_test.dart -d macos \
//     --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>
//
// Every measurement is printed as a line starting with "RESULT "; face
// strips (2× of the preview) and 100 % crops go to
// `<container tmp>/lumen_retouch2/` (original | before | after | after +
// parsing, left to right).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_parsing_cache.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/portrait/retouch_parsing.dart';
import 'package:lumen/features/portrait/retouch_tiles.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import '../test/engine/retouch_harness.dart' show gpuRetouch;
import '../test/support/test_images.dart' show diffStats;

const _samplePath = String.fromEnvironment('LUMEN_RAW_SAMPLE');

void _r(String line) => debugPrint('RESULT $line');

String _mb(num bytes) => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

/// Bytes of the GPU textures of [m] (low + five double-width atlases).
int _atlasBytes(RetouchMaps m) => m.width * m.height * 4 * 11;

/// The v2 analysis grid (the whole decode at a long edge of 1024–2048
/// aiming at 160 px for the smallest face): what "before" means.
RgbaBuffer _v2Grid(RgbaBuffer decode, FaceAnalysis faces) {
  final iods = [
    for (var k = 0; k < faces.faces.length; k++)
      FaceFrame.tryCreate(faces.faces[k], k, decode.width, decode.height)?.iod,
  ].whereType<double>();
  final srcLong = math.max(decode.width, decode.height);
  final want = srcLong * 160 / iods.reduce(math.min);
  final le = math.min(srcLong, want.clamp(1024, 2048).ceil());
  return AuxMaps.proxy(decode, longEdge: le);
}

/// [full]'s window `(x0, y0, w, h)` through the CPU twin of pass R.
RgbaBuffer _retouchWindow(
  RgbaBuffer full,
  RetouchMaps? maps,
  RetouchUniforms u,
  int x0,
  int y0,
  int w,
  int h,
) {
  final out = RgbaBuffer(w, h);
  final k = maps == null ? null : RetouchKernel(maps, u);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sx = (x0 + x).clamp(0, full.width - 1);
      final sy = (y0 + y).clamp(0, full.height - 1);
      final s = full.offset(sx, sy), o = out.offset(x, y);
      out.data.setRange(o, o + 4, full.data, s);
      k?.retouchPixel(
        full.data[s],
        full.data[s + 1],
        full.data[s + 2],
        (sx + 0.5) / full.width,
        (sy + 0.5) / full.height,
        out.data,
        o,
      );
    }
  }
  return out;
}

/// Side-by-side strip of [parts], each scaled by [zoom] (nearest).
RgbaBuffer _strip(List<RgbaBuffer> parts, int zoom) {
  final w = parts.first.width, h = parts.first.height;
  final out = RgbaBuffer((w * zoom + 8) * parts.length, h * zoom);
  for (var i = 0; i < parts.length; i++) {
    final ox = i * (w * zoom + 8);
    for (var y = 0; y < h * zoom; y++) {
      for (var x = 0; x < w * zoom; x++) {
        final s = parts[i].offset(x ~/ zoom, y ~/ zoom);
        final o = out.offset(ox + x, y);
        out.data.setRange(o, o + 4, parts[i].data, s);
      }
    }
  }
  return out;
}

void _png(String dir, String name, RgbaBuffer b) {
  final im = img.Image.fromBytes(
    width: b.width,
    height: b.height,
    bytes: b.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  File(p.join(dir, '$name.png')).writeAsBytesSync(img.encodePng(im));
}

/// [faces] with face 0 copied to an [n]-face grid at [scale] of its size
/// (a group shot for the memory budget; the crops show whatever is there).
FaceAnalysis _group(FaceAnalysis faces, int n, double scale) {
  final f = faces.faces.first;
  final lm = f.landmarks;
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < lm.length; i += 2) {
    cx += lm[i];
    cy += lm[i + 1];
  }
  cx /= lm.length / 2;
  cy /= lm.length / 2;
  final cols = 4, rows = (n / cols).ceil();
  return FaceAnalysis(
    imageWidth: faces.imageWidth,
    imageHeight: faces.imageHeight,
    modelVersion: faces.modelVersion,
    faces: [
      for (var k = 0; k < n; k++)
        () {
          final tx = (k % cols + 0.5) / cols, ty = (k ~/ cols + 0.5) / rows;
          double mx(double x) => tx + (x - cx) * scale;
          double my(double y) => ty + (y - cy) * scale;
          return DetectedFace(
            id: 'g$k',
            box: FaceBox(
              mx(f.box.x),
              my(f.box.y),
              f.box.width * scale,
              f.box.height * scale,
            ),
            landmarks: [
              for (var i = 0; i < lm.length; i += 2) ...[
                mx(lm[i]),
                my(lm[i + 1]),
              ],
            ],
          );
        }(),
    ],
  );
}

/// Mean skin weight (0..1) over source pixels where [where] holds.
double _skinWhere(
  RetouchMaps m,
  RgbaBuffer grid,
  bool Function(double u, double v) where,
) {
  var sum = 0.0, n = 0;
  for (var y = 0; y < grid.height; y += 2) {
    for (var x = 0; x < grid.width; x += 2) {
      final u = (x + 0.5) / grid.width, v = (y + 0.5) / grid.height;
      if (!where(u, v)) continue;
      sum += m.sourceRegion(RetouchChannel.skin, u, v) / 255;
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real photo: full-resolution face tiles and parsing-based skin masks',
    () async {
      final out = p.join(Directory.systemTemp.path, 'lumen_retouch2');
      Directory(out).createSync(recursive: true);
      final root = Directory.systemTemp.createTempSync('lumen_retouch2_cat');
      addTearDown(() => root.deleteSync(recursive: true));
      final catalog = FileCatalogRepository(root.path);
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(catalog),
          // Never write test data into the app's real caches.
          faceCacheProvider.overrideWith((ref) async => MemoryFaceCache()),
          faceParsingCacheProvider.overrideWith(
            (ref) async => MemoryFaceParsingCache(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final imported = await container
          .read(importServiceProvider)
          .importOne(
            ImportFile(
              name: p.basename(_samplePath),
              bytes: File(_samplePath).readAsBytesSync(),
            ),
          );
      final id = (imported as Imported).entry.assetId;
      final faces = (await container.read(faceAnalysisProvider(id).future))
          .analysis;
      final decode = (await loadAnalysisPixels(catalog, id)).pixels;
      final fullImage = await decodePhoto(await catalog.readPixelSource(id));
      final full = await rgbaFromImage(fullImage);
      fullImage.dispose();
      _r(
        'photo ${full.width}x${full.height}, decode '
        '${decode.width}x${decode.height}, ${faces.faces.length} faces',
      );
      expect(faces.faces, isNotEmpty);

      // ---- Before: the v2 analysis grid -------------------------------
      final grid = _v2Grid(decode, faces);
      var sw = Stopwatch()..start();
      final before = computeRetouchMaps(grid, faces);
      final beforeMs = sw.elapsedMilliseconds;

      // ---- After: full-resolution tiles, heuristic masks ----------------
      final rss0 = ProcessInfo.currentRss;
      sw = Stopwatch()..start();
      final tiles = await loadFaceTiles(catalog, id, faces);
      final tilesMs = sw.elapsedMilliseconds;
      sw = Stopwatch()..start();
      final after = computeRetouchMaps(decode, faces, tiles: tiles);
      final afterMs = sw.elapsedMilliseconds;

      // ---- Parsing: Selfie Multiclass on each tile ---------------------
      final service = container.read(faceParsingServiceProvider);
      sw = Stopwatch()..start();
      final parsing = await service.parse(id, tiles, download: false);
      final parseMs = sw.elapsedMilliseconds;
      expect(parsing, isNotNull, reason: 'Selfie Multiclass not on device');
      sw = Stopwatch()..start();
      final parsed = computeRetouchMaps(
        decode,
        faces,
        tiles: tiles,
        parsing: parsing,
      );
      final parsedMs = sw.elapsedMilliseconds;
      final rss1 = ProcessInfo.currentRss;
      _r(
        'build: before (v2 grid ${grid.width}x${grid.height}) $beforeMs ms; '
        'after: tiles (full decode + crops) $tilesMs ms + maps $afterMs ms; '
        'parsing $parseMs ms + maps $parsedMs ms; RSS '
        '${_mb(rss0)} → ${_mb(rss1)}',
      );
      _r(
        'textures: before ${before.width}x${before.height} '
        '${_mb(_atlasBytes(before))}; after atlas '
        '${after.width}x${after.height} ${_mb(_atlasBytes(after))}; tiles '
        '${_mb(tiles.fold(0, (a, t) => a + t.pixels.data.length))}',
      );

      // ---- Fine-scale detection ----------------------------------------
      for (var k = 0; k < after.faces.length; k++) {
        final fb = before.faces[k], fa = after.faces[k];
        final fullIod = FaceFrame.tryCreate(
          faces.faces[fa.slot],
          fa.slot,
          full.width,
          full.height,
        )!.iod;
        double px(double iod) => fullIod / iod;
        List<BlemishCandidate> spots(RetouchMaps m) =>
            m.blemishes.where((b) => b.faceId == fa.faceId).toList();
        double minR(List<BlemishCandidate> s) => s.isEmpty
            ? double.nan
            : s.map((b) => b.radiusIod * fullIod).reduce(math.min);
        final sb = spots(before), sa = spots(after), sp = spots(parsed);
        _r(
          'face ${fa.faceId}: IOD full-res ${fullIod.toStringAsFixed(0)} px; '
          'analysed ${fb.iod.toStringAsFixed(0)} → '
          '${fa.iod.toStringAsFixed(0)} px; one map texel = '
          '${px(fb.iod).toStringAsFixed(2)} → ${px(fa.iod).toStringAsFixed(2)} '
          'full-res px; finest band σ0 '
          '${(math.max(0.8, 0.006 * fb.iod) * px(fb.iod)).toStringAsFixed(1)} '
          '→ ${(math.max(0.8, 0.006 * fa.iod) * px(fa.iod)).toStringAsFixed(1)}'
          ' full-res px; spot candidates ${sb.length} → ${sa.length} '
          '(parsing ${sp.length}), smallest radius '
          '${minR(sb).toStringAsFixed(1)} → ${minR(sa).toStringAsFixed(1)} '
          'full-res px; smooth need n2 ${fb.skin.n2.toStringAsFixed(4)} → '
          '${fa.skin.n2.toStringAsFixed(4)}',
        );
      }

      // ---- Parsing vs heuristic on the parser's own classes -------------
      final planes = parsing!;
      double cls(ParsingClass c, double u, double v) {
        var best = 0.0;
        for (final q in planes) {
          best = math.max(best, q.sample(c, u, v));
        }
        return best;
      }

      bool hair(double u, double v) => cls(ParsingClass.hair, u, v) > 0.6;
      bool body(double u, double v) => cls(ParsingClass.bodySkin, u, v) > 0.6;
      bool clothes(double u, double v) => cls(ParsingClass.clothes, u, v) > 0.6;
      _r(
        'skin weight on parser hair ${_skinWhere(after, decode, hair).toStringAsFixed(3)}'
        ' → ${_skinWhere(parsed, decode, hair).toStringAsFixed(3)}; on body '
        'skin (neck, ears, hands) ${_skinWhere(after, decode, body).toStringAsFixed(3)}'
        ' → ${_skinWhere(parsed, decode, body).toStringAsFixed(3)}; on clothes '
        '${_skinWhere(after, decode, clothes).toStringAsFixed(3)} → '
        '${_skinWhere(parsed, decode, clothes).toStringAsFixed(3)}',
      );

      // ---- GPU (Metal) vs CPU twin, preview vs full-resolution ---------
      final u = RetouchUniforms.fromSettings(
        PortraitSettings.empty
            .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 80)
            .withGroupValue(FaceGroup.all, PortraitIds.skinEven, 60)
            .withGroupValue(FaceGroup.all, PortraitIds.skinShine, 60)
            .withGroupValue(FaceGroup.all, PortraitIds.acne, 100)
            .withGroupValue(FaceGroup.all, PortraitIds.darkCircles, 50),
        faces,
      );
      final cpu = applyRetouch(decode, parsed, u);
      final gpu = await gpuRetouch(decode, parsed, u);
      final d = diffStats(gpu, cpu);
      var luma = 0.0;
      for (var i = 0; i < gpu.data.length; i += 4) {
        luma += gpu.data[i] + gpu.data[i + 1] + gpu.data[i + 2];
      }
      luma /= 3 * gpu.data.length / 4;
      _r(
        'GPU vs CPU on the ${decode.width} px preview: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255; GPU mean luma '
        '${luma.toStringAsFixed(1)} (not white)',
      );
      expect(d.max, lessThanOrEqualTo(4));
      expect(luma, lessThan(230));
      sw = Stopwatch()..start();
      final gpuFull = await gpuRetouch(full, parsed, u, tileSize: 2048);
      final fullMs = sw.elapsedMilliseconds;
      // Compare the retouch change at both sizes on the preview grid.
      final pFull = AuxMaps.proxy(
        gpuFull,
        longEdge: decode.width > decode.height ? decode.width : decode.height,
      );
      final pSrc = AuxMaps.proxy(
        full,
        longEdge: decode.width > decode.height ? decode.width : decode.height,
      );
      var dd = 0.0, changed = 0;
      for (var i = 0; i < gpu.data.length; i++) {
        if (i % 4 == 3) continue;
        final a = gpu.data[i] - decode.data[i];
        final b = pFull.data[i] - pSrc.data[i];
        if (a != 0 || b != 0) {
          dd += (a - b).abs();
          changed++;
        }
      }
      _r(
        'export at ${full.width}x${full.height} (tiles 2048) $fullMs ms; '
        'retouch change preview vs full-res downsampled: mean '
        '${(dd / math.max(1, changed)).toStringAsFixed(2)}/255 over $changed '
        'touched channels',
      );
      expect(dd / math.max(1, changed), lessThan(2.5));

      // ---- Strips and 100 % crops --------------------------------------
      for (var k = 0; k < after.faces.length; k++) {
        final face = faces.faces[after.faces[k].slot];
        final fd = FaceFrame.tryCreate(face, k, decode.width, decode.height)!;
        final b = fd.bounds;
        _png(
          out,
          'strip_face${k}_2x',
          _strip([
            for (final m in [null, before, after, parsed])
              _retouchWindow(decode, m, u, b.x0, b.y0, b.w, b.h),
          ], 2),
        );
        final ff = FaceFrame.tryCreate(face, k, full.width, full.height)!;
        final s = (0.9 * ff.iod).round();
        for (final (name, c) in [
          ('cheek', ff.p(FaceMesh.rightCheekApple)),
          ('hairline', ff.p(FaceMesh.foreheadTop)),
          ('eye', ff.p(FaceMesh.rightIrisCenter)),
          ('lips', ff.mid(FaceMesh.lipsOuter.first, FaceMesh.lipsOuter[10])),
        ]) {
          final x0 = (c.x - s / 2).round(), y0 = (c.y - s / 2).round();
          _png(
            out,
            'crop100_face${k}_$name',
            _strip([
              for (final m in [null, before, after, parsed])
                _retouchWindow(full, m, u, x0, y0, s, s),
            ], 1),
          );
        }
      }
      _r('strips and crops in $out');

      // ---- Memory and time for 1, 2 and 8 faces -----------------------
      for (final n in [1, 2, 8]) {
        final group = n == 2
            ? faces
            : (n == 1
                  ? FaceAnalysis(
                      imageWidth: faces.imageWidth,
                      imageHeight: faces.imageHeight,
                      modelVersion: faces.modelVersion,
                      faces: [faces.faces.first],
                    )
                  : _group(faces, 8, 0.45));
        sw = Stopwatch()..start();
        final t = await loadFaceTiles(catalog, id, group);
        final tMs = sw.elapsedMilliseconds;
        sw = Stopwatch()..start();
        final m = computeRetouchMaps(decode, group, tiles: t);
        final mMs = sw.elapsedMilliseconds;
        final px = t.fold(0, (a, x) => a + x.plan.width * x.plan.height);
        _r(
          '$n faces: tiles ${t.length} (${(px / 1e6).toStringAsFixed(2)} MP, '
          'IOD ${m.faces.map((f) => f.iod.round()).join('/')}), tiles '
          '$tMs ms + maps $mMs ms, atlas ${m.width}x${m.height} = '
          '${_mb(_atlasBytes(m))} GPU',
        );
        expect(px, lessThanOrEqualTo(kTileBudgetPx * 1.05));
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: _samplePath.isEmpty,
  );
}
