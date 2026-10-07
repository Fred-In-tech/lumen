import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'synthetic_landmarks.dart';
import 'synthetic_portrait.dart';

/// Ground-truth class of a synthetic face at local (x, y), like Selfie
/// Multiclass would label it: face skin (features included: the model
/// calls eyes, brows and lips face skin too), hair (head and fringe),
/// body skin (neck), accessories (glasses rims) or background.
ParsingClass synthClassAt(SynthFace f, double x, double y) {
  if (synthOnRim(f, x, y)) return ParsingClass.accessories;
  final ry = y < kOvalCy ? 1.65 : kOvalRyBottom;
  final skinR = math.pow(x / kOvalRx, 2) + math.pow((y - kOvalCy) / ry, 2);
  final headR = math.pow(x / 1.4, 2) + math.pow((y - 0.2) / 1.85, 2);
  if (skinR <= 1) {
    if (f.fringe && y > kFringeY0 && y < kFringeY1) return ParsingClass.hair;
    return ParsingClass.faceSkin;
  }
  if (headR <= 1 && y < 0.9) return ParsingClass.hair;
  if (f.neck && x.abs() < kNeckHalfW && y > kNeckY0 && y < kNeckY1) {
    return ParsingClass.bodySkin;
  }
  return ParsingClass.background;
}

/// Parsing planes for [plan]'s tile of [p], as a segmentation model would
/// give them: [size] cells on the long side (a 256 model over a tile),
/// 3×3 supersampled, then softened by one cell.
FaceParsingPlanes synthParsing(
  SynthPortrait p,
  FaceTilePlan plan, {
  int size = 96,
}) {
  final f = p.faces.firstWhere((x) => x.id == plan.faceId);
  final k = size / math.max(plan.width, plan.height);
  final w = math.max(1, (plan.width * k).round());
  final h = math.max(1, (plan.height * k).round());
  final planes = List.generate(6, (_) => Float32List(w * h));
  final iw = p.image.width, ih = p.image.height;
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      for (var sy = 0; sy < 3; sy++) {
        for (var sx = 0; sx < 3; sx++) {
          final u = plan.u0 + (plan.u1 - plan.u0) * (i + (sx + 0.5) / 3) / w;
          final v = plan.v0 + (plan.v1 - plan.v0) * (j + (sy + 0.5) / 3) / h;
          final q = f.toLocal(u * iw, v * ih);
          planes[synthClassAt(f, q.x, q.y).index][j * w + i] += 1 / 9;
        }
      }
    }
  }
  Uint8List soft(Float32List c) {
    final out = Uint8List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        var s = 0.0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = i + dx, y = j + dy;
            if (x < 0 || y < 0 || x >= w || y >= h) continue;
            s += c[y * w + x];
            n++;
          }
        }
        out[j * w + i] = (255 * s / n).round();
      }
    }
    return out;
  }

  final b = [for (final c in planes) soft(c)];
  return FaceParsingPlanes(
    faceId: plan.faceId,
    cropX: plan.u0,
    cropY: plan.v0,
    cropWidth: plan.u1 - plan.u0,
    cropHeight: plan.v1 - plan.v0,
    width: w,
    height: h,
    background: b[0],
    hair: b[1],
    bodySkin: b[2],
    faceSkin: b[3],
    clothes: b[4],
    accessories: b[5],
  );
}
