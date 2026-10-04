import '../model/face_analysis.dart';
import '../model/portrait.dart';
import '../render/rgba_buffer.dart';
import 'blemish_types.dart';
import 'face_parsing_input.dart';
import 'retouch_kernel.dart';
import 'retouch_maps_builder.dart';
import 'retouch_uniforms.dart';

/// One-shot portrait retouch (thumbnails, batch export, tests): builds the
/// maps and applies the pass. Returns [src] itself when the settings are
/// the identity for every face (no maps are built).
RgbaBuffer retouchImage(
  RgbaBuffer src,
  FaceAnalysis analysis,
  PortraitSettings settings, {
  List<FaceParsingPlanes>? parsing,
  BlemishOverrides overrides = BlemishOverrides.none,
}) {
  final uniforms = RetouchUniforms.fromSettings(settings, analysis);
  if (uniforms.isIdentity) return src;
  final maps = computeRetouchMaps(
    src,
    analysis,
    parsing: parsing,
    overrides: overrides,
  );
  return applyRetouch(src, maps, uniforms);
}
