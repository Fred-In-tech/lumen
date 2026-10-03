import 'dart:typed_data';

import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'aux_maps.dart';
import 'develop_kernel.dart';
import 'geometry_mapping.dart';
import 'rgba_buffer.dart';
import 'tone_lut.dart';
import 'uniform_layout.dart';

/// True when [s] uses a spatial op that reads the aux maps.
bool needsAuxMaps(DevelopSettings s) =>
    s.value(P.dehaze) != 0 ||
    s.value(P.shadows) != 0 ||
    s.value(P.highlights) != 0 ||
    s.value(P.clarity) != 0;

/// CPU reference implementation of the develop pipeline (engine `lumen-1`).
///
/// The GPU `develop.frag` matches this within the parity thresholds of
/// PLAN.md §6.3. The local auto-tone solver and guards render proxies with
/// it. Output size follows the geometry (see [outputSizeFor]).
///
/// [aux] are the precomputed spatial maps of this photo; pass them when
/// rendering the same photo repeatedly (solver loops). When omitted they are
/// computed from [source] (only if a spatial op is active). Noise reduction,
/// sharpening and grain (pre/finish passes) are not part of the reference.
RgbaBuffer renderReference(
  RgbaBuffer source,
  DevelopSettings settings, {
  AuxMaps? aux,
  bool showClipping = false,
}) {
  final maps =
      aux ??
      (needsAuxMaps(settings)
          ? AuxMaps.compute(AuxMaps.proxy(source))
          : AuxMaps.neutral());
  final size = outputSizeFor(source.width, source.height, settings.geometry);
  final f = DevelopUniforms.pack(
    settings,
    DevelopContext(
      outWidth: size.width,
      outHeight: size.height,
      sourceWidth: source.width,
      sourceHeight: source.height,
      auxWidth: maps.width,
      auxHeight: maps.height,
      airlight: maps.airlight,
      showClipping: showClipping,
    ),
  );
  final kernel = DevelopKernel(source, f, ToneLut.bake(settings), maps);
  final out = RgbaBuffer(size.width, size.height);
  final px = Float64List(4);
  var o = 0;
  for (var y = 0; y < size.height; y++) {
    for (var x = 0; x < size.width; x++, o += 4) {
      kernel.shade(x, y, px);
      out.data[o] = (px[0] * 255).round();
      out.data[o + 1] = (px[1] * 255).round();
      out.data[o + 2] = (px[2] * 255).round();
      out.data[o + 3] = (px[3] * 255).round();
    }
  }
  return out;
}
