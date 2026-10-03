import 'package:lumen_core/lumen_core.dart';
void main() {
  for (final id in SceneId.values) {
    final s = SyntheticScenes.build(id);
    final i = s.image;
    print('${id.name.padRight(20)} med=${SceneMetrics.medianLuma(i).toStringAsFixed(3)} p0.5=${SceneMetrics.percentileLuma(i,0.005).toStringAsFixed(3)} p99.5=${SceneMetrics.percentileLuma(i,0.995).toStringAsFixed(3)} clip=${(SceneMetrics.clipFraction(i)*100).toStringAsFixed(2)}% crush=${(SceneMetrics.crushFraction(i)*100).toStringAsFixed(2)}% sigL=${SceneMetrics.sigmaLStar(i).toStringAsFixed(1)} C=${SceneMetrics.meanChroma(i).toStringAsFixed(1)} a=${SceneMetrics.castA(i, s.neutralPatches.isEmpty?null:s.neutralPatches).toStringAsFixed(3)}');
  }
}
