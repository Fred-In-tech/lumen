import 'package:lumen_core/lumen_core.dart';
String f(double v) => v.toStringAsFixed(3);
void main() {
  final sc = SyntheticScenes.overexposedBeach();
  final src = makeProxy(sc.image, longEdge: 256);
  for (final s in [
    {P.exposure: -0.5},
    {P.exposure: -0.5, P.highlights: -20.0},
    {P.exposure: -0.5, P.highlights: -20.0, P.dehaze: 30.0},
    {P.exposure: -0.5, P.highlights: -20.0, P.blacks: -40.0},
    {P.exposure: -0.5, P.highlights: -20.0, P.blacks: -40.0, P.contrast: 40.0},
  ]) {
    final o = renderReference(src, DevelopSettings.defaults.withValues(s));
    final m = ImageStats.compute(o);
    print('$s med=${f(m.lumaP.p50)} phi=${f(m.highlightP99_5)} p0.5=${f(m.lumaP.p0_5)} p99.5=${f(m.lumaP.p99_5)}');
  }
}
