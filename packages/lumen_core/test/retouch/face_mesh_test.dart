import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_landmarks.dart';

void main() {
  group('FaceMesh index map', () {
    final loops = <String, List<int>>{
      'faceOval': FaceMesh.faceOval,
      'rightEye': FaceMesh.rightEye,
      'leftEye': FaceMesh.leftEye,
      'lipsOuter': FaceMesh.lipsOuter,
      'lipsInner': FaceMesh.lipsInner,
      'nose': FaceMesh.nose,
      'forehead': FaceMesh.forehead,
    };

    test('every index is a valid MediaPipe landmark', () {
      final all = [
        ...loops.values.expand((l) => l),
        ...FaceMesh.rightUnderEye4,
        ...FaceMesh.leftUnderEye4,
        ...FaceMesh.rightIrisRing,
        ...FaceMesh.leftIrisRing,
        FaceMesh.rightIrisCenter,
        FaceMesh.leftIrisCenter,
      ];
      expect(all.every((i) => i >= 0 && i < FaceMesh.landmarkCount), isTrue);
    });

    test('closed loops have the documented sizes and no repeats', () {
      expect(FaceMesh.faceOval, hasLength(36));
      expect(FaceMesh.rightEye, hasLength(16));
      expect(FaceMesh.leftEye, hasLength(16));
      expect(FaceMesh.lipsOuter, hasLength(20));
      expect(FaceMesh.lipsInner, hasLength(20));
      for (final e in loops.entries) {
        expect(e.value.toSet(), hasLength(e.value.length), reason: e.key);
      }
    });

    test('lower lids are the outer-to-inner halves of the eye loops', () {
      expect(FaceMesh.rightLowerLid.first, FaceMesh.rightEye.first);
      expect(FaceMesh.rightLowerLid.last, FaceMesh.rightEye[8]);
      expect(
        FaceMesh.rightLowerLid.skip(1).take(7),
        FaceMesh.rightEye.sublist(9).reversed,
      );
      expect(
        FaceMesh.leftLowerLid.skip(1).take(7),
        FaceMesh.leftEye.sublist(9).reversed,
      );
    });

    test('paired right/left lists have equal lengths', () {
      final pairs = [
        (FaceMesh.rightUnderEye2, FaceMesh.leftUnderEye2),
        (FaceMesh.rightUnderEye3, FaceMesh.leftUnderEye3),
        (FaceMesh.rightUnderEye4, FaceMesh.leftUnderEye4),
        (FaceMesh.rightBrowLower, FaceMesh.leftBrowLower),
        (FaceMesh.rightBrowUpper, FaceMesh.leftBrowUpper),
        (FaceMesh.rightNostril, FaceMesh.leftNostril),
        (FaceMesh.rightJaw, FaceMesh.leftJaw),
      ];
      for (final (r, l) in pairs) {
        expect(r.length, l.length);
      }
    });
  });

  group('synthetic landmarks', () {
    final m = synthLandmarksLocal();

    test('place all 478 indices', () {
      expect(m, hasLength(FaceMesh.landmarkCount));
    });

    test('IOD is 1 and the eyes are horizontal', () {
      final r = m[FaceMesh.rightIrisCenter]!, l = m[FaceMesh.leftIrisCenter]!;
      expect(l.x - r.x, closeTo(1, 1e-12));
      expect(l.y, r.y);
      expect(m[33]!.x, lessThan(m[133]!.x), reason: 'right eye on image left');
    });

    test('under-eye rings move down and out', () {
      for (var k = 0; k < 9; k++) {
        final r2 = m[FaceMesh.rightUnderEye2[k]]!;
        final r3 = m[FaceMesh.rightUnderEye3[k]]!;
        final r4 = m[FaceMesh.rightUnderEye4[k]]!;
        expect(r3.y, greaterThan(r2.y));
        expect(r4.y, greaterThan(r3.y));
      }
      final outer2 = m[FaceMesh.rightUnderEye2.first]!;
      final outer4 = m[FaceMesh.rightUnderEye4.first]!;
      expect(outer4.x, lessThan(outer2.x), reason: 'outer ends move out');
    });
  });
}
