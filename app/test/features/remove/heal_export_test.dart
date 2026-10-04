import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

/// Patch area (source px) of the test op.
const _box = PixelBox(60, 40, 50, 30);

Future<(MemoryCatalogRepository, String, int, int)> _photo() async {
  final repo = MemoryCatalogRepository();
  final s = SyntheticScenes.build(SceneId.values.first, longEdge: 240).image;
  final jpeg = img.encodeJpg(
    img.Image.fromBytes(
      width: s.width,
      height: s.height,
      bytes: s.data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ).convert(numChannels: 3),
    quality: 95,
  );
  final r = await ImportService(repo)
      .importOne(ImportFile(name: 'p.jpg', bytes: Uint8List.fromList(jpeg)));
  final entry = (r as Imported).entry;
  return (repo, entry.assetId, entry.width, entry.height);
}

HealOp _op(int w, int h) => HealOp.forPatch(
  id: 'h1',
  bbox: _box,
  srcWidth: w,
  srcHeight: h,
  engine: 'patchmatch@1',
  ai: false,
  strokes: const [],
);

img.Image _decode(Uint8List png) => img.decodePng(png)!;

bool _same(img.Image a, img.Image b, int x, int y) {
  final p = a.getPixel(x, y), q = b.getPixel(x, y);
  return p.r == q.r && p.g == q.g && p.b == q.b;
}

class _FullMask implements AiMaskRasterLoader {
  final List<String> loads = [];

  @override
  Future<MaskRaster?> load(String assetId, String maskRef) async {
    loads.add(maskRef);
    return MaskRaster(4, 4, Uint8List(16)..fillRange(0, 16, 255));
  }
}

void main() {
  test('an export with a heal op differs from one without, inside the '
      'patch box only', () async {
    final (repo, id, w, h) = await _photo();
    final store = MemoryPatchStore();
    await store.save(
      id,
      'retouch/h1.png',
      RgbaBuffer.filled(_box.width, _box.height, 255, 0, 0),
    );
    final service = ExportService(repo, patches: () async => store);
    const png = ExportOptions(format: ExportFormat.png);

    final plain = _decode((await service.exportOne(id, png)).bytes);
    await repo.saveEdit(
      EditDocument.create(id).copyWith(
        settings: DevelopSettings.defaults.copyWith(heal: [_op(w, h)]),
      ),
    );
    final healed = _decode((await service.exportOne(id, png)).bytes);

    expect((healed.width, healed.height), (w, h));
    var inside = 0, outside = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inBox =
            x >= _box.x && x < _box.right && y >= _box.y && y < _box.bottom;
        final same = _same(plain, healed, x, y);
        if (inBox && !same) inside++;
        if (!inBox && !same) outside++;
      }
    }
    expect(inside, greaterThan(_box.area * 0.95));
    expect(outside, 0, reason: 'pixels no patch covers are untouched');
    final c = healed.getPixel(_box.x + 25, _box.y + 15);
    expect((c.r, c.g, c.b), (255, 0, 0));

    // Hidden ops do not export; without a store, heal ops are ignored.
    await repo.saveEdit(
      EditDocument.create(id).copyWith(
        settings: DevelopSettings.defaults.copyWith(
          heal: [_op(w, h).copyWith(hidden: true)],
        ),
      ),
    );
    final hidden = _decode((await service.exportOne(id, png)).bytes);
    expect(_same(plain, hidden, _box.x + 25, _box.y + 15), isTrue);
  });

  test('batch thumbnails draw heal ops (scaled to the thumbnail)', () async {
    final (repo, id, w, h) = await _photo();
    final store = MemoryPatchStore();
    await store.save(
      id,
      'retouch/h1.png',
      RgbaBuffer.filled(_box.width, _box.height, 255, 0, 0),
    );
    final settings = DevelopSettings.defaults.copyWith(heal: [_op(w, h)]);
    await refreshThumbnail(repo, id, settings, patches: () async => store);
    final thumb = _decode((await repo.readThumb(id))!);
    final k = thumb.width / w;
    final c = thumb.getPixel(
      ((_box.x + 25) * k).round(),
      ((_box.y + 15) * k).round(),
    );
    expect(c.r, greaterThan(200));
    expect(c.g, lessThan(60));
  });

  test('AI mask rasters reach the export renderer', () async {
    final (repo, id, _, _) = await _photo();
    final loader = _FullMask();
    final service = ExportService(repo, maskLoader: loader);
    const png = ExportOptions(format: ExportFormat.png);
    final plain = _decode((await service.exportOne(id, png)).bytes);
    await repo.saveEdit(
      EditDocument.create(id).copyWith(
        settings: DevelopSettings.defaults.copyWith(
          masks: [
            LocalMask(
              id: 'm1',
              name: 'Subject 1',
              kind: MaskKind.subject,
              shape: const AiShape(maskRef: 'masks/m1.png').toJson(),
              adjustments: const {P.exposure: 1.5},
            ),
          ],
        ),
      ),
    );
    final masked = _decode((await service.exportOne(id, png)).bytes);
    expect(loader.loads, ['masks/m1.png']);
    final a = plain.getPixel(20, 20), b = masked.getPixel(20, 20);
    expect(b.r + b.g + b.b, greaterThan(a.r + a.g + a.b + 30));
  });
}
