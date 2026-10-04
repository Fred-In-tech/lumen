import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/remove/remove_jobs.dart';
import 'package:lumen/platform/cancellable_task.dart';

/// Web: no isolates here, so the model pipeline runs inline.
CancellableTask<InpaintResult> startModelRemoval(
  CancellableRunner run,
  HealInput input,
  InpaintModel model,
  InpaintConfig config,
) => run(() {
  final source = input.healedBase();
  final hole = rasterizeHoleMask(input.strokes, source.width, source.height);
  return InpaintPipeline.remove(
    source,
    hole,
    model: model,
    method: InpaintMethod.model,
    config: config,
  );
});
