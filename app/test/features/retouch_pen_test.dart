import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

const _n = 320;
const _face = SynthFace(id: 'f', cx: 160, cy: 110, iod: 88, penPatches: true);
final _portrait = renderSynthPortrait(_n, _n, const [_face]);

/// An erase stroke over the chin stubble.
BrushStroke get _erase {
  final a = _face.toPx(kStubbleX - kStubbleRx, kStubbleY);
  final b = _face.toPx(kStubbleX + kStubbleRx, kStubbleY);
  return BrushStroke(
    points: [(a.x / _n, a.y / _n), (b.x / _n, b.y / _n)],
    radius: (kStubbleRy + 0.04) * _face.iod / _n,
    hardness: 0.8,
    erase: true,
  );
}

final _smooth = PortraitSettings.empty.withGroupValue(
  FaceGroup.all,
  PortraitIds.skinSoftening,
  100,
);

Future<MemoryCatalogRepository> _catalog() async {
  final repo = MemoryCatalogRepository();
  final b = _portrait.image;
  await repo.add(
    CatalogEntry(
      assetId: 'p',
      fileName: 'p.png',
      originalPath: 'originals/p.png',
      format: 'png',
      width: _n,
      height: _n,
      bytes: 1,
      importedAt: DateTime.utc(2026),
    ),
    Uint8List.fromList(
      img.encodePng(
        img.Image.fromBytes(
          width: _n,
          height: _n,
          bytes: b.data.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        ),
      ),
    ),
  );
  return repo;
}

bool _inStubble(int x, int y) {
  final q = _face.toLocal(x + 0.5, y + 0.5);
  final sx = (q.x - kStubbleX) / (0.8 * kStubbleRx);
  final sy = (q.y - kStubbleY) / (0.8 * kStubbleRy);
  return sx * sx + sy * sy <= 1;
}

/// Within the erase stroke's footprint (plus two pixels of interpolation).
bool _nearStroke(int x, int y) {
  final e = _erase;
  final (ax, ay) = e.points.first;
  final (bx, by) = e.points.last;
  final px = (x + 0.5) / _n, py = (y + 0.5) / _n;
  final dx = bx - ax, dy = by - ay;
  var t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
  t = t < 0 ? 0 : (t > 1 ? 1 : t);
  final ex = (px - ax - t * dx) * _n, ey = (py - ay - t * dy) * _n;
  return ex * ex + ey * ey <= (e.radius * _n + 2) * (e.radius * _n + 2);
}

void main() {
  test('a pen stroke re-applies only the pen, never the analysis', () async {
    final repo = await _catalog();
    await repo.saveEdit(
      EditDocument.create('p').copyWith(
        settings: DevelopSettings.defaults.copyWith(portrait: _smooth),
      ),
    );
    final baseMaps = computeRetouchMaps(_portrait.image, _portrait.analysis);
    var baseBuilds = 0;
    final c = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        retouchBaseMapsProvider('p').overrideWith((ref) async {
          baseBuilds++;
          return (maps: baseMaps, faces: _portrait.analysis);
        }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider('p').future);
    final before = await c.read(retouchMapsBuildProvider('p').future);
    expect(identical(before?.maps, baseMaps), isTrue, reason: 'no pen yet');
    final editor = c.read(editorProvider('p').notifier);
    final settings = c.read(editorProvider('p')).value!.settings;
    editor.commit(
      settings.copyWith(portrait: settings.portrait.withSkinPen([_erase])),
      label: 'Skin pen',
    );
    final pen = await c.read(retouchMapsBuildProvider('p').future);
    expect(pen?.maps.regionA, isNot(baseMaps.regionA));
    expect(identical(pen?.maps.b1, baseMaps.b1), isTrue);
    expect(baseBuilds, 1, reason: 'the analysis did not re-run');
    // An unrelated edit keeps the same pen maps (content-compared pen).
    final now = c.read(editorProvider('p')).value!.settings;
    editor.commit(
      now.copyWith(
        portrait: now.portrait.withGroupValue(
          FaceGroup.all,
          PortraitIds.skinSoftening,
          80,
        ),
      ),
      label: 'Smooth',
    );
    final again = await c.read(retouchMapsBuildProvider('p').future);
    expect(identical(again?.maps, pen?.maps), isTrue);
    expect(baseBuilds, 1);
  });

  test('export applies the pen', () async {
    final repo = await _catalog();
    final cache = MemoryFaceCache();
    await cache.write(
      'p',
      FaceCacheEntry(models: kFaceModels, analysis: _portrait.analysis),
    );
    final service = ExportService(
      repo,
      retouch: StoredRetouchLoader(
        catalog: repo,
        faceService: () async => FaceAnalysisService(
          cache: cache,
          models: kFaceModels,
          analyzer: () => Future.error(const InferenceUnavailable('unused')),
        ),
      ).load,
    );
    Future<img.Image> export(PortraitSettings portrait) async {
      await repo.saveEdit(
        EditDocument.create('p').copyWith(
          settings: DevelopSettings.defaults.copyWith(portrait: portrait),
        ),
      );
      final out = await service.exportOne(
        'p',
        const ExportOptions(format: ExportFormat.png),
      );
      return img.decodePng(out.bytes)!;
    }

    final plain = await export(PortraitSettings.empty);
    final smoothed = await export(_smooth);
    final penned = await export(_smooth.withSkinPen([_erase]));
    var smoothChanged = 0, penChanged = 0, total = 0, elsewhere = 0;
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        final p0 = plain.getPixel(x, y);
        final p1 = smoothed.getPixel(x, y), p2 = penned.getPixel(x, y);
        if (_inStubble(x, y)) {
          total++;
          if (p1 != p0) smoothChanged++;
          if (p2 != p0) penChanged++;
        } else if (p1 != p2 && !_nearStroke(x, y)) {
          elsewhere++;
        }
      }
    }
    expect(smoothChanged, greaterThan(total ~/ 2));
    expect(penChanged, 0, reason: 'erased stubble exported untouched');
    expect(elsewhere, 0, reason: 'nothing changes beyond the stroke');
  });
}
