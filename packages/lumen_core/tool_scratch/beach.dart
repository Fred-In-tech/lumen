import 'package:lumen_core/lumen_core.dart';
String f(double v) => v.toStringAsFixed(3);
void main() {
  final sc = SyntheticScenes.overexposedBeach();
  final r = LocalAutoTone.run(proxy: sc.image);
  print(r.settings.nonDefaultValues);
  final out = renderReference(sc.image, r.settings);
  final st1 = ImageStats.compute(makeProxy(out, longEdge: 256));
  print('R1 med=${f(SceneMetrics.medianLuma(out))} p0.5=${f(st1.lumaP.p0_5)} key1=${f(LocalAutoTone.sceneKey(st1))} sigma=${f(st1.sigmaLStar)} haze=${f(st1.haze)} hiClip=${f(st1.hiClip)}');
  final small = makeProxy(out, longEdge: 256);
  for (final s in [
    {P.whites: 50.0},
    {P.contrast: 40.0},
    {P.vibrance: -25.0, P.saturation: -6.3},
    {P.whites: 50.0, P.contrast: 40.0, P.vibrance: -25.0, P.saturation: -6.3},
  ]) {
    final o = renderReference(small, DevelopSettings.defaults.withValues(s));
    print('$s med=${f(SceneMetrics.medianLuma(o))}');
  }
}
