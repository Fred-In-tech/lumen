import 'dart:math' as math;
import 'dart:typed_data';

import '../model/face_analysis.dart';
import 'face_mesh.dart';
import 'map_rect.dart';

/// Faces smaller than this (IOD in source pixels) get no automatic retouch
/// (research 07 §1.2 step 5).
const double kMinFaceIodSourcePx = 24;

/// Retouch work never leaves the face bbox scaled by this (§1.4).
const double kFaceRectScale = 1.8;

/// Inside that limit, the work rect is the face bbox plus this margin (IOD
/// units): enough for the 0.35 IOD forehead extension, the feathers and
/// the skin reference blur, and about half the area of the full × 1.8.
const double kFaceMarginIod = 0.5;

/// Ownership centre: this far (IOD) below the eye midpoint, ≈ the nose.
const double kOwnershipCenterIod = 0.45;

/// Derived geometry of one face on a map grid (all lengths in map pixels;
/// research 07 §1.2 "derived geometry").
class FaceFrame {
  FaceFrame._({
    required this.slot,
    required this.faceId,
    required this.xs,
    required this.ys,
    required this.iod,
    required this.eyeMid,
    required this.axis,
    required this.irisRadiusRight,
    required this.irisRadiusLeft,
    required this.bounds,
    required this.rect,
  });

  /// Builds the frame for [face] on a `gridW × gridH` grid, or null when
  /// the face has too few landmarks or an IOD below [minIod] map pixels.
  static FaceFrame? tryCreate(
    DetectedFace face,
    int slot,
    int gridW,
    int gridH, {
    double minIod = 0,
  }) {
    if (face.landmarkCount < FaceMesh.landmarkCount) return null;
    final n = FaceMesh.landmarkCount;
    final xs = Float64List(n), ys = Float64List(n);
    for (var i = 0; i < n; i++) {
      xs[i] = face.landmarks[2 * i] * gridW;
      ys[i] = face.landmarks[2 * i + 1] * gridH;
    }
    double dist(int a, int b) =>
        math.sqrt(math.pow(xs[a] - xs[b], 2) + math.pow(ys[a] - ys[b], 2));
    final iod = dist(FaceMesh.rightIrisCenter, FaceMesh.leftIrisCenter);
    if (!iod.isFinite || iod <= math.max(minIod, 1e-6)) return null;
    double irisR(int c, List<int> ring) =>
        ring.map((i) => dist(c, i)).reduce((a, b) => a + b) / ring.length;
    final mid = (
      x: (xs[FaceMesh.rightIrisCenter] + xs[FaceMesh.leftIrisCenter]) / 2,
      y: (ys[FaceMesh.rightIrisCenter] + ys[FaceMesh.leftIrisCenter]) / 2,
    );
    var ax = xs[FaceMesh.menton] - mid.x, ay = ys[FaceMesh.menton] - mid.y;
    final al = math.sqrt(ax * ax + ay * ay);
    if (al < 1e-6) return null;
    ax /= al;
    ay /= al;
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final i in FaceMesh.faceOval) {
      x0 = math.min(x0, xs[i]);
      y0 = math.min(y0, ys[i]);
      x1 = math.max(x1, xs[i]);
      y1 = math.max(y1, ys[i]);
    }
    final b = face.box;
    if (b.width > 0 && b.height > 0) {
      x0 = math.min(x0, b.x * gridW);
      y0 = math.min(y0, b.y * gridH);
      x1 = math.max(x1, (b.x + b.width) * gridW);
      y1 = math.max(y1, (b.y + b.height) * gridH);
    }
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    final hw = (x1 - x0) / 2, hh = (y1 - y0) / 2;
    return FaceFrame._(
      slot: slot,
      faceId: face.id,
      xs: xs,
      ys: ys,
      iod: iod,
      eyeMid: mid,
      axis: (x: ax, y: ay),
      irisRadiusRight: irisR(FaceMesh.rightIrisCenter, FaceMesh.rightIrisRing),
      irisRadiusLeft: irisR(FaceMesh.leftIrisCenter, FaceMesh.leftIrisRing),
      bounds: MapRect.around(cx, cy, hw, hh, gridW, gridH),
      rect: MapRect.around(
        cx,
        cy,
        math.min(hw * kFaceRectScale, hw + kFaceMarginIod * iod),
        math.min(hh * kFaceRectScale, hh + kFaceMarginIod * iod),
        gridW,
        gridH,
      ),
    );
  }

  /// Uniform slot (index in `FaceAnalysis.faces`).
  final int slot;
  final String faceId;

  /// Landmark positions in continuous map pixel coordinates.
  final Float64List xs;
  final Float64List ys;

  /// Inter-ocular distance (iris centre 468 ↔ 473), map pixels.
  final double iod;

  /// Midpoint between the iris centres.
  final MapPoint eyeMid;

  /// Unit vector from [eyeMid] toward the chin (152).
  final MapPoint axis;
  final double irisRadiusRight;
  final double irisRadiusLeft;

  /// Face oval (and detector box) bounds, clipped to the grid.
  final MapRect bounds;

  /// Work rect: [bounds] + [kFaceMarginIod], at most [bounds] ×
  /// [kFaceRectScale], clipped to the grid.
  final MapRect rect;

  MapPoint p(int i) => (x: xs[i], y: ys[i]);

  List<MapPoint> pts(List<int> indices) => [for (final i in indices) p(i)];

  /// Midpoint of landmarks [a] and [b].
  MapPoint mid(int a, int b) =>
      (x: (xs[a] + xs[b]) / 2, y: (ys[a] + ys[b]) / 2);

  /// Signed distance of [q] along [axis] from [eyeMid] (positive = toward
  /// the chin).
  double alongAxis(MapPoint q) =>
      (q.x - eyeMid.x) * axis.x + (q.y - eyeMid.y) * axis.y;

  /// Normalized distance of pixel centre `(x, y)` from this face (used to
  /// assign overlapping rect pixels to one face: smaller wins).
  double ownershipDistance(int x, int y) {
    // Face centre ≈ the nose, 0.45 IOD below the eye midpoint.
    final cx = eyeMid.x + kOwnershipCenterIod * iod * axis.x;
    final cy = eyeMid.y + kOwnershipCenterIod * iod * axis.y;
    final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
    return math.sqrt(dx * dx + dy * dy) / iod;
  }
}
