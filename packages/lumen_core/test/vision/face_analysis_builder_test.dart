import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_face.dart';

const _w = 1000, _h = 800;

FaceCandidate candidate({
  required double cx,
  double iod = 100,
  double yaw = 0,
  double presence = 0.95,
  bool withMesh = true,
  double score = 0.9,
}) => FaceCandidate(
  detection: syntheticDetection(
    x: cx - 100,
    y: 300,
    size: 200,
    imageWidth: _w,
    imageHeight: _h,
    score: score,
  ),
  landmarks: withMesh
      ? syntheticLandmarks(
          imageWidth: _w,
          imageHeight: _h,
          cx: cx,
          cy: 400,
          iod: iod,
          yawDegrees: yaw,
        )
      : const [],
  presence: presence,
);

void main() {
  test('applies reject rules, orders left→right, ids are faceKeys', () {
    final result = buildFaceAnalysis(
      imageWidth: _w,
      imageHeight: _h,
      modelVersion: 'det@1+mesh@1',
      candidates: [
        candidate(cx: 700),
        candidate(cx: 200, presence: 0.2),
        candidate(cx: 450, iod: 20),
        candidate(cx: 850, yaw: 65),
        candidate(cx: 300),
        candidate(cx: 550, withMesh: false),
      ],
    );
    final a = result.analysis;
    expect(a.modelVersion, 'det@1+mesh@1');
    expect(a.imageWidth, _w);
    expect(a.faces.map((f) => f.box.centerX * _w), [
      closeTo(300, 1e-9),
      closeTo(700, 1e-9),
    ]);
    for (final f in a.faces) {
      expect(f.id, faceKey(f.box));
      expect(f.landmarkCount, 478);
      expect(f.confidence, 0.9);
      expect(f.tagSource, TagSource.auto);
    }
    expect(
      {for (final r in result.rejected) r.reason},
      {
        FaceRejectReason.lowPresence,
        FaceRejectReason.tooSmall,
        FaceRejectReason.extremeYaw,
      },
    );
    expect(result.rejected, hasLength(4));
  });

  test('colliding keys get -2, -3 suffixes', () {
    final result = buildFaceAnalysis(
      imageWidth: _w,
      imageHeight: _h,
      modelVersion: 'v',
      candidates: [candidate(cx: 500), candidate(cx: 500, score: 0.8)],
    );
    final ids = result.analysis.faces.map((f) => f.id).toList();
    expect(ids, [ids.first, '${ids.first}-2']);
  });

  test('rejected faces round-trip through JSON', () {
    const r = RejectedFace(
      id: 'f3_4',
      box: FaceBox(0.1, 0.2, 0.3, 0.4),
      reason: FaceRejectReason.extremeYaw,
      confidence: 0.7,
    );
    expect(RejectedFace.fromJson(r.toJson()), r);
  });

  test('carryOverManualTags keeps user tags across re-analysis', () {
    final first = buildFaceAnalysis(
      imageWidth: _w,
      imageHeight: _h,
      modelVersion: 'old',
      candidates: [candidate(cx: 300), candidate(cx: 700)],
    ).analysis;
    final id = first.faces.last.id;
    final tagged = first.withTag(id, FaceGroup.child, personId: 'p1');
    final rerun = buildFaceAnalysis(
      imageWidth: _w,
      imageHeight: _h,
      modelVersion: 'new',
      candidates: [candidate(cx: 300), candidate(cx: 700)],
    ).analysis;

    final merged = carryOverManualTags(tagged, rerun);

    expect(merged.modelVersion, 'new');
    final f = merged.faceById(id)!;
    expect(f.group, FaceGroup.child);
    expect(f.personId, 'p1');
    expect(f.tagSource, TagSource.manual);
    expect(merged.faces.first.tagSource, TagSource.auto);
    expect(carryOverManualTags(rerun, rerun), same(rerun));
  });
}
