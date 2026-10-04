import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/import/photo_decoder.dart';

/// GPU full-resolution export render (tiled). Falls back to the CPU path.
Future<RgbaBuffer> gpuFullResRender(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge, {
  String assetId = '',
}) async {
  final ShaderLibrary shaders;
  try {
    shaders = await ShaderLibrary.load();
  } on ShaderLoadException {
    final decoded = await decodePhoto(original, maxLongEdge: longEdge);
    final src = await rgbaFromImage(decoded);
    decoded.dispose();
    return renderReference(src, settings);
  }
  final source = await ExportRenderer.decodeOriginal(original);
  final aux = await AuxTextures.build(source);
  try {
    final px = await ExportRenderer(shaders).render(
      source: source,
      aux: aux,
      settings: settings,
      assetId: assetId,
      longEdge: longEdge,
    );
    return RgbaBuffer(px.width, px.height, px.rgba);
  } finally {
    aux.dispose();
    EngineImages.dispose(source);
  }
}

/// GPU export of decoded (healed) source pixels: portrait retouch (pass R),
/// AI masks and the develop/finish passes, tiled, with aux maps built from
/// the source it is given. Falls back to [CpuSourceRenderer] when shaders
/// cannot load.
class GpuSourceRenderer implements SourceRenderer {
  const GpuSourceRenderer();

  @override
  int? decodeLongEdge(int? longEdge) => kMaxExportEdge;

  @override
  Future<RgbaBuffer> render(
    RgbaBuffer source,
    DevelopSettings settings,
    SourceInputs inputs, {
    int? longEdge,
  }) async {
    final ShaderLibrary shaders;
    try {
      shaders = await ShaderLibrary.load();
    } on ShaderLoadException {
      return const CpuSourceRenderer().render(
        source,
        settings,
        inputs,
        longEdge: longEdge,
      );
    }
    final img = await imageFromRgba(source);
    final aux = await AuxTextures.build(img);
    try {
      final px = await ExportRenderer(shaders).render(
        source: img,
        aux: aux,
        settings: settings,
        assetId: inputs.assetId,
        longEdge: longEdge,
        maskRasters: inputs.maskRasters,
        faceAnalysis: inputs.faces,
        retouchMaps: inputs.retouchMaps,
        backdropAssets: await exportBackdropAssets(
          source,
          settings.backdrop,
          inputs.backdrop,
        ),
      );
      return RgbaBuffer(px.width, px.height, px.rgba);
    } finally {
      aux.dispose();
      img.dispose();
    }
  }
}

/// Backdrop textures for an export of decoded [source] pixels: the matte is
/// refined against [source] at the preview resolution (2560 px long edge,
/// like the editor), off the UI isolate. Null when [b] is off or there is
/// no raster. Pass it to `ExportRenderer.render(backdropAssets:)`.
Future<BackdropAssets?> exportBackdropAssets(
  RgbaBuffer source,
  BackdropChange b,
  BackdropInputs inputs,
) async {
  if (b.isNone || (inputs.people == null && inputs.hair == null)) {
    return null;
  }
  return compute(_exportAssets, (source, b, inputs));
}

const int _backdropPreviewEdge = 2560;

BackdropAssets _exportAssets((RgbaBuffer, BackdropChange, BackdropInputs) r) {
  final (source, b, inputs) = r;
  final base = BackdropBase.build(
    AuxMaps.proxy(source, longEdge: _backdropPreviewEdge),
    people: inputs.people,
    hair: inputs.hair,
  );
  return BackdropAssets.build(base, b, image: inputs.image);
}
