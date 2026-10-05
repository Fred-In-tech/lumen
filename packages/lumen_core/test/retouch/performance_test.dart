import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_portrait.dart';

void main() {
  test('1024² two-face maps + apply run well under 3 s (JIT)', () {
    final p = renderSynthPortrait(1024, 1024, [
      const SynthFace(id: 'a', cx: 300, cy: 380, iod: 150),
      const SynthFace(id: 'b', cx: 740, cy: 420, iod: 130),
    ]);
    var s = PortraitSettings.empty;
    for (final e in {
      PortraitIds.skinSoftening: 60.0,
      PortraitIds.skinEven: 40.0,
      PortraitIds.acne: 80.0,
      PortraitIds.darkCircles: 50.0,
      PortraitIds.eyeBags: 40.0,
      PortraitIds.eyeWhites: 80.0,
      PortraitIds.iris: 80.0,
      PortraitIds.teethDesaturate: 50.0,
      PortraitIds.skinShine: 40.0,
    }.entries) {
      s = s.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    final u = RetouchUniforms.fromSettings(s, p.analysis);
    final sw = Stopwatch()..start();
    final maps = computeRetouchMaps(p.image, p.analysis);
    final mapsMs = sw.elapsedMilliseconds;
    final out = applyRetouch(p.image, maps, u);
    final totalMs = sw.elapsedMilliseconds;
    printOnFailure('maps $mapsMs ms, apply ${totalMs - mapsMs} ms');
    expect(maps.faces, hasLength(2));
    expect(identical(out, p.image), isFalse);
    expect(totalMs, lessThan(3000));
  });
}
