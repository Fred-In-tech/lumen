import 'package:lumen_core/lumen_core.dart';
String f(double v) => v.toStringAsFixed(3);
void main() {
  for (final id in [SceneId.overexposedBeach, SceneId.tungstenCast, SceneId.hazyLandscape, SceneId.wellExposedChart]) {
    final sc = SyntheticScenes.build(id);
    final r = LocalAutoTone.run(proxy: sc.image, exif: sc.exif);
    final out = renderReference(sc.image, r.settings);
    final st1 = ImageStats.compute(makeProxy(out, longEdge: 256));
    final st0 = ImageStats.compute(makeProxy(sc.image, longEdge: 256));
    final r2 = LocalAutoTone.run(proxy: out);
    print('${id.name} key0=${f(LocalAutoTone.sceneKey(st0))} key1=${f(LocalAutoTone.sceneKey(st1))} lavg ${f(st0.lAvg)}/${f(st1.lAvg)} p1 ${f(st0.yP1)}/${f(st1.yP1)} p99 ${f(st0.yP99)}/${f(st1.yP99)} med1=${f(SceneMetrics.medianLuma(out))} exp=${f(r.settings.value(P.exposure))} pass2 exp=${f(r2.settings.value(P.exposure))} wb1 a=${f(st1.wb.a)}');
  }
}
