import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen/features/editor/renderer/gpu_source_renderer.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('FloatExport');

/// Stats of the most recent float export (diagnostics and on-device tests).
FloatExportStats? lastFloatExportStats;

/// The float export of the app (docs/HIGH_BIT_DEPTH.md §Export): photos
/// with a float source ([loader]) on a device that passes the float probe
/// are exported from windows of that source, tile by tile, so highlight
/// headroom and shadow precision reach the file without a full-resolution
/// float image on the GPU. Returns null for every other photo, and when
/// the float source fails: the caller then exports on the 8-bit path.
FloatExportRenderer gpuFloatExport(FloatSourceLoader loader) =>
    (request) => _export(loader, request);

Future<RgbaBuffer?> _export(
  FloatSourceLoader loader,
  FloatExportRequest r,
) async {
  final ShaderLibrary shaders;
  try {
    shaders = await ShaderLibrary.load();
  } on ShaderLoadException {
    return null;
  }
  if (!await HbdCapability.probe(shaders)) return null;
  final source = await loader(r.assetId);
  if (source == null) return null;
  AuxTextures? aux;
  try {
    final settings = r.settings;
    final virt = ExportRenderer.floatSourceSize(
      source.width,
      source.height,
      settings.geometry,
      longEdge: r.longEdge,
    );
    // Heal patches: one premultiplied overlay at the size the source is
    // rendered at, cut per window by the renderer.
    final visible = [
      for (final op in settings.heal)
        if (!op.hidden && op.isRenderable) op,
    ];
    final getStore = r.patches;
    final patches = getStore == null || visible.isEmpty
        ? const <String, RgbaBuffer>{}
        : await loadPatchMap(await getStore(), r.assetId, visible);
    final lookup = MapPatchLookup(patches);
    final overlay = patches.isEmpty
        ? null
        : await runInBackground(
            () => composeHealOverlay(virt.width, virt.height, visible, lookup),
          );
    // Aux maps from an analysis-size float decode (with the heals in).
    final le = math.max(virt.width, virt.height);
    final k = math.min(1.0, kAnalysisLongEdge / le);
    final pw = math.max(1, (virt.width * k).round());
    final ph = math.max(1, (virt.height * k).round());
    var proxy = (await source.render(fullWidth: pw, fullHeight: ph)).buffer;
    if (patches.isNotEmpty) {
      proxy = composeOverlayFloat(
        proxy,
        composeHealOverlay(pw, ph, visible, lookup),
      );
    }
    aux = await AuxTextures.fromFloatProxy(proxy);
    // The backdrop matte is refined against the 8-bit rendition, as in
    // the editor.
    final swap = r.backdrop;
    BackdropAssets? assets;
    if (!settings.backdrop.isNone &&
        (swap.people != null || swap.hair != null)) {
      final rendition = await decodeHealedSource(
        r.pixelSource,
        assetId: r.assetId,
        ops: settings.heal,
        patches: r.patches,
        maxLongEdge: 2560,
      );
      assets = await exportBackdropAssets(rendition, settings.backdrop, swap);
    }
    final px = await ExportRenderer(shaders).renderFloat(
      source: source,
      aux: aux,
      settings: settings,
      assetId: r.assetId,
      longEdge: r.longEdge,
      maskRasters: r.maskRasters,
      faceAnalysis: r.faces,
      retouchMaps: r.retouchMaps,
      backdropAssets: assets,
      healOverlay: overlay,
      onStats: (stats) {
        lastFloatExportStats = stats;
        _log.info('float export of ${r.assetId}: $stats');
      },
    );
    return RgbaBuffer(px.width, px.height, px.rgba);
  } on FloatSourceException catch (e) {
    _log.warning('float export failed, using the 8-bit path: $e');
    return null;
  } finally {
    aux?.dispose();
    unawaited(source.release());
  }
}
