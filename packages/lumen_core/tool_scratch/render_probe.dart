import 'package:lumen_core/lumen_core.dart';
void main() {
  final src = SyntheticScenes.darkInterior(longEdge: 256).image;
  for (final s in [
    DevelopSettings.defaults,
    DevelopSettings.defaults.withValues({P.exposure: 2}),
    DevelopSettings.defaults.withValues({P.exposure: 2, P.shadows: 60}),
    DevelopSettings.defaults.withValues({P.exposure: 2, P.whites: 50, P.blacks: 20}),
    DevelopSettings.defaults.withValues({P.exposure: 2, P.contrast: 40}),
    DevelopSettings.defaults.withValues({P.temp: -50}),
  ]) {
    final sw = Stopwatch()..start();
    try {
      final out = renderReference(src, s);
      print('${s.nonDefaultValues} ${sw.elapsedMilliseconds}ms med=${SceneMetrics.medianLuma(out).toStringAsFixed(3)} a=${SceneMetrics.castA(out).toStringAsFixed(3)}');
    } catch (e) { print('ERR $e'); }
  }
}
