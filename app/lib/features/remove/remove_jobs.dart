/// The background halves of `RemoveService`: plain data in, plain data
/// out. Each `start…` function is top-level so its closure captures only
/// its input (closures sent to an isolate must not capture UI objects).
library;

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/platform/cancellable_task.dart';

/// What a removal will do, decided before any pixels move.
class RemovalPlan {
  const RemovalPlan({required this.method, required this.faceIntersect});

  /// Nothing to remove (the strokes miss the photo).
  const RemovalPlan.empty() : method = null, faceIntersect = false;

  final InpaintMethod? method;
  final bool faceIntersect;

  bool get isEmpty => method == null;
}

class PlanInput {
  const PlanInput({
    required this.strokes,
    required this.width,
    required this.height,
    required this.faces,
    required this.modelAvailable,
    this.forced,
  });

  final List<BrushStroke> strokes;
  final int width;
  final int height;
  final List<FaceBox> faces;
  final bool modelAvailable;
  final InpaintMethod? forced;
}

/// Rasterizes the hole, picks the engine and checks the faces.
RemovalPlan planRemoval(PlanInput input) {
  final hole = rasterizeHoleMask(input.strokes, input.width, input.height);
  if (hole.isEmpty) return const RemovalPlan.empty();
  final method =
      input.forced ??
      InpaintMethodPicker.pick(
        HoleStats.measure(hole),
        modelAvailable: input.modelAvailable,
      );
  return RemovalPlan(
    method: method,
    faceIntersect: holeIntersectsFaces(hole, input.faces),
  );
}

CancellableTask<RemovalPlan> startPlan(
  CancellableRunner run,
  PlanInput input,
) => run(() => planRemoval(input));

/// The photo as the user sees it before a new op: [source] with the
/// [existing] ops' [patches] drawn in, so new fills sample earlier fixes.
class HealInput {
  const HealInput({
    required this.source,
    required this.existing,
    required this.patches,
    required this.strokes,
  });

  final RgbaBuffer source;
  final List<HealOp> existing;
  final Map<String, RgbaBuffer> patches;
  final List<BrushStroke> strokes;

  RgbaBuffer healedBase() => existing.isEmpty || patches.isEmpty
      ? source
      : composeHealed(source, existing, MapPatchLookup(patches));
}

/// Classical removal ([method] must not be [InpaintMethod.model]).
CancellableTask<InpaintResult> startClassicalRemoval(
  CancellableRunner run,
  HealInput input,
  InpaintMethod method,
  InpaintConfig config,
) => run(
  () => runInpaintJob(
    InpaintJob(
      source: input.healedBase(),
      strokes: input.strokes,
      method: method,
      config: config,
    ),
  ),
);

/// Clone stamp ([kind] clone, [offsetPx] required) or healing brush
/// ([kind] heal, null [offsetPx] = best nearby donor). Null when the
/// strokes miss the photo.
CancellableTask<InpaintPatch?> startBrush(
  CancellableRunner run,
  HealInput input,
  HealKind kind,
  (int, int)? offsetPx,
) => run(() {
  final source = input.healedBase();
  final hole = rasterizeHoleMask(input.strokes, source.width, source.height);
  return switch (kind) {
    HealKind.clone => clonePatch(source, hole, offsetPx ?? (0, 0)),
    HealKind.heal => healPatch(source, hole, offset: offsetPx),
    HealKind.remove => throw ArgumentError.value(kind, 'kind'),
  };
});
