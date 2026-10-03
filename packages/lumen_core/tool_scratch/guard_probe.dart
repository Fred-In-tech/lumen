import 'package:lumen_core/lumen_core.dart';
void main() {
  final s = SyntheticScenes.wellExposedChart();
  for (final ev in [0.8, 1.0, 1.2, 1.4, 1.6]) {
    final st = DevelopSettings.defaults.withValue(P.exposure, ev);
    final g = Guards.enforce(proxy: s.image, settings: st);
    print('ev=$ev clip ${(g.before.clipFraction*100).toStringAsFixed(2)}% -> ${(g.after.clipFraction*100).toStringAsFixed(2)}% ${g.settings.nonDefaultValues} ${g.reasons}');
  }
}
