import 'package:lumen_core/lumen_core.dart';
String f(double v) => v.toStringAsFixed(2);
void main() {
  for (final id in [SceneId.darkInterior, SceneId.overexposedBeach, SceneId.tungstenCast, SceneId.daylightCoolCast, SceneId.greenCast, SceneId.hazyLandscape, SceneId.wellExposedChart, SceneId.goldenHourPortrait]) {
    final sc = SyntheticScenes.build(id);
    final sw = Stopwatch()..start();
    final r = LocalAutoTone.run(proxy: sc.image, exif: sc.exif);
    final t = sw.elapsedMilliseconds;
    final out = renderReference(sc.image, r.settings);
    final np = sc.neutralPatches.isEmpty ? null : sc.neutralPatches;
    final a0 = SceneMetrics.castA(sc.image, np), a1 = SceneMetrics.castA(out, np);
    // idempotence
    final r2 = LocalAutoTone.run(proxy: out);
    print('${id.name.padRight(19)} ${t}ms n=${r.renders} key=${f(r.keyTarget)} med ${f(SceneMetrics.medianLuma(sc.image))}->${f(SceneMetrics.medianLuma(out))} clip=${(SceneMetrics.clipFraction(out)*100).toStringAsFixed(2)}% sig ${f(SceneMetrics.sigmaLStar(sc.image))}->${f(SceneMetrics.sigmaLStar(out))} castA ${f(a0)}->${f(a1)}');
    print('   ${r.settings.nonDefaultValues.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2))))}');
    print('   pass2: exp=${f(r2.settings.value(P.exposure))} temp=${f(r2.settings.value(P.temp))} ${r2.settings.nonDefaultValues.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(1))))}');
  }
}
