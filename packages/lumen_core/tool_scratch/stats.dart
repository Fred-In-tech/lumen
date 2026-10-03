import 'package:lumen_core/lumen_core.dart';
void main() {
  for (final id in SceneId.values) {
    final sw = Stopwatch()..start();
    final s = ImageStats.compute(SyntheticScenes.build(id).image);
    print('${id.name.padRight(20)} ${sw.elapsedMilliseconds}ms haze=${s.haze.toStringAsFixed(3)} sig=${s.sigmaLStar.toStringAsFixed(1)} wb=${s.wb.a.toStringAsFixed(3)},${s.wb.m.toStringAsFixed(3)},c${s.wb.confidence.toStringAsFixed(2)} lAvg=${s.lAvg.toStringAsFixed(4)} yP1=${s.yP1.toStringAsFixed(4)} yP99=${s.yP99.toStringAsFixed(4)} C=${s.meanChroma.toStringAsFixed(1)} skin=${s.skinShare.toStringAsFixed(3)} json=${s.toJson()['hslShare']}');
  }
}
