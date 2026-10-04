import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

/// A person matte covering the left half of the frame.
MaskRaster _leftHalf() {
  const w = 64, h = 48;
  final d = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w ~/ 2; x++) {
      d[y * w + x] = 255;
    }
  }
  return MaskRaster(w, h, d);
}

void main() {
  test('export applies the background swap outside the person only', () async {
    final repo = MemoryCatalogRepository();
    final s = SyntheticScenes.build(SceneId.values.first, longEdge: 240).image;
    final png = img.encodePng(
      img.Image.fromBytes(
        width: s.width,
        height: s.height,
        bytes: s.data.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      ),
    );
    final r = await ImportService(repo)
        .importOne(ImportFile(name: 'p.png', bytes: Uint8List.fromList(png)));
    final id = (r as Imported).entry.assetId;
    var loads = 0;
    Future<BackdropInputs> loader(String assetId, BackdropChange c) async {
      loads++;
      return (people: _leftHalf(), hair: null, image: null);
    }

    final service = ExportService(
      repo,
      backdrop: loader,
      sourceRenderer: const CpuSourceRenderer(),
    );
    const opts = ExportOptions(format: ExportFormat.png);
    final plain = img.decodePng((await service.exportOne(id, opts)).bytes)!;
    expect(loads, 0, reason: 'no swap: nothing is segmented');

    await repo.saveEdit(
      EditDocument.create(id).copyWith(
        settings: DevelopSettings.defaults.copyWith(
          backdrop: const BackdropChange(
            mode: BackdropMode.color,
            color: 0xFF0000FF,
            spill: 0,
          ),
        ),
      ),
    );
    final out = img.decodePng((await service.exportOne(id, opts)).bytes)!;
    expect(loads, 1);
    // Far right (background): pure blue. Far left (person): unchanged.
    final bg = out.getPixel(out.width - 5, out.height ~/ 2);
    expect(bg.b, greaterThan(240));
    expect(bg.r, lessThan(15));
    final person = out.getPixel(5, out.height ~/ 2);
    final before = plain.getPixel(5, plain.height ~/ 2);
    expect((person.r - before.r).abs(), lessThanOrEqualTo(2));
    expect((person.g - before.g).abs(), lessThanOrEqualTo(2));
  });
}
