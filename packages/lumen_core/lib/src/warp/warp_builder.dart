/// Builds the warp field of a photo (face reshape + liquify). Pure data in,
/// pure data out: [buildWarpField] runs unchanged in `Isolate.run`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/develop_settings.dart';
import '../model/face_analysis.dart';
import '../model/liquify.dart';
import '../model/portrait.dart';
import 'face_warp.dart';
import 'liquify.dart';
import 'warp_field.dart';

/// Inputs of [buildWarpField] (isolate-safe).
class WarpRequest {
  const WarpRequest({
    required this.sourceWidth,
    required this.sourceHeight,
    this.faces,
    this.portrait = PortraitSettings.empty,
    this.liquify = const [],
    this.longEdge = kWarpLongEdge,
  });

  /// From the develop settings of a photo of [sourceWidth]×[sourceHeight].
  factory WarpRequest.fromSettings(
    DevelopSettings s,
    FaceAnalysis? faces, {
    required int sourceWidth,
    required int sourceHeight,
  }) => WarpRequest(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    faces: faces,
    portrait: s.portrait,
    liquify: s.liquify,
  );

  final int sourceWidth;
  final int sourceHeight;
  final FaceAnalysis? faces;
  final PortraitSettings portrait;
  final List<LiquifyStroke> liquify;
  final int longEdge;
}

/// Warp grid size: long edge ≤ [longEdge], source aspect, never upscaled.
({int width, int height}) warpGridSize(
  int srcW,
  int srcH, {
  int longEdge = kWarpLongEdge,
}) {
  final le = math.max(srcW, srcH);
  if (le <= longEdge) {
    return (width: math.max(1, srcW), height: math.max(1, srcH));
  }
  final s = longEdge / le;
  return (
    width: math.max(1, (srcW * s).round()),
    height: math.max(1, (srcH * s).round()),
  );
}

/// Resolved shape values of every face with landmarks (empty = none).
List<FaceShape> resolveFaceShapes(PortraitSettings p, FaceAnalysis? faces) => [
  for (final f in faces?.faces ?? const <DetectedFace>[])
    FaceShape.resolve(p, f),
];

/// Changes exactly when the face-reshape part of the field changes.
int warpShapeKey(PortraitSettings p, FaceAnalysis? faces) => Object.hash(
  identityHashCode(faces),
  Object.hashAll([for (final s in resolveFaceShapes(p, faces)) ...s.values]),
);

/// True when [s] warps the photo (shape sliders on a face, or liquify).
bool hasWarpEdits(DevelopSettings s, FaceAnalysis? faces) =>
    s.liquify.isNotEmpty ||
    resolveFaceShapes(s.portrait, faces).any((f) => !f.isIdentity);

/// The face-reshape field only (the base liquify strokes compose onto).
WarpField buildShapeField(WarpRequest r) {
  final faces = r.faces?.faces ?? const <DetectedFace>[];
  final shapes = [for (final f in faces) FaceShape.resolve(r.portrait, f)];
  if (shapes.every((s) => s.isIdentity) && r.liquify.isEmpty) {
    return WarpField.identity();
  }
  final g = warpGridSize(r.sourceWidth, r.sourceHeight, longEdge: r.longEdge);
  final dx = Float32List(g.width * g.height), dy = Float32List(dx.length);
  for (var k = 0; k < faces.length; k++) {
    addFaceReshape(
      faces[k],
      shapes[k],
      srcW: r.sourceWidth,
      srcH: r.sourceHeight,
      gw: g.width,
      gh: g.height,
      dx: dx,
      dy: dy,
    );
  }
  return WarpField(g.width, g.height, dx, dy);
}

/// The full field: face reshape, then the liquify strokes in order.
WarpField buildWarpField(WarpRequest r) {
  final base = buildShapeField(r);
  if (r.liquify.isEmpty) return base;
  return applyLiquifyStrokes(
    base,
    r.liquify,
    sourceWidth: r.sourceWidth,
    sourceHeight: r.sourceHeight,
  );
}

/// A full field plus the field before its last liquify stroke, so a live
/// (growing) last stroke can be re-applied incrementally.
typedef WarpBuildResult = ({WarpField prefix, WarpField full});

/// [buildWarpField] that also returns the prefix field (isolate-safe).
WarpBuildResult buildWarpWithPrefix(WarpRequest r) {
  final base = buildShapeField(r);
  final n = r.liquify.length;
  if (n == 0) return (prefix: base, full: base);
  final prefix = applyLiquifyStrokes(
    base,
    r.liquify.sublist(0, n - 1),
    sourceWidth: r.sourceWidth,
    sourceHeight: r.sourceHeight,
  );
  return (
    prefix: prefix,
    full: applyLiquifyStrokes(
      prefix,
      [r.liquify.last],
      sourceWidth: r.sourceWidth,
      sourceHeight: r.sourceHeight,
    ),
  );
}
