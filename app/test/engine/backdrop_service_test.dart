import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/backdrop_service.dart';
import 'package:lumen_core/lumen_core.dart';

import 'backdrop_harness.dart';

const _blue = BackdropChange(mode: BackdropMode.color, color: 0xFF2050C0);
const _ms = Duration(milliseconds: 1);

void main() {
  final scene = SwapScene.make(w: 120, h: 90);
  late List<BackdropAssets?> published;
  late int baseBuilds;
  late int assetBuilds;
  late bool failBase;

  BackdropService make() => BackdropService(
    preview: () async => scene.image,
    onAssets: published.add,
    buildBase: (r) async {
      baseBuilds++;
      if (failBase) throw StateError('no matte');
      return BackdropBase.build(r.source, people: r.people, hair: r.hair);
    },
    buildAssets: (r) async {
      assetBuilds++;
      return BackdropAssets.build(r.base, r.change, image: r.image);
    },
  );

  setUp(() {
    published = [];
    baseBuilds = 0;
    assetBuilds = 0;
    failBase = false;
  });

  test('off, or no subject raster: the pass stays off, nothing builds', () {
    fakeAsync((async) {
      final svc = make();
      svc.update(BackdropChange.none);
      svc.update(_blue); // no rasters yet
      async.elapse(_ms * 100);
      expect(published.whereType<BackdropAssets>(), isEmpty);
      expect(baseBuilds + assetBuilds, 0);
      expect(svc.assets, isNull);
    });
  });

  test('first change builds at once; colour edits are uniforms only', () {
    fakeAsync((async) {
      final svc = make()..setInputs(people: scene.people);
      svc.update(_blue);
      async.flushTimers();
      expect(published.length, 1);
      final a = published.single!;
      for (final b in [
        _blue.copyWith(color: 0xFFFF0000),
        _blue.copyWith(mode: BackdropMode.gradient, angle: 20),
        _blue.copyWith(spill: 90, match: 30),
      ]) {
        svc.update(b);
        async.elapse(_ms * 100);
      }
      expect(published.length, 1);
      expect(svc.assets, same(a));
      expect((baseBuilds, assetBuilds), (1, 1));
    });
  });

  test(
    'edge drags rebuild at most every 80 ms; old textures stay meanwhile',
    () {
      fakeAsync((async) {
        final svc = make()..setInputs(people: scene.people);
        svc.update(_blue);
        async.flushTimers();
        final first = svc.assets;
        for (var f = 10.0; f <= 30; f += 10) {
          svc.update(_blue.copyWith(feather: f));
          async.elapse(_ms * 20);
        }
        expect(svc.assets, same(first)); // 60 ms in: still the old ones
        for (var f = 40.0; f <= 100; f += 10) {
          svc.update(_blue.copyWith(feather: f));
          async.elapse(_ms * 20);
        }
        async.elapse(_ms * 100);
        expect(svc.assets!.fits(_blue.copyWith(feather: 100), null), isTrue);
        expect(baseBuilds, 1);
        // 10 changes over 200 ms: one build per 80 ms window, plus the last.
        expect(assetBuilds, lessThanOrEqualTo(4));
      });
    },
  );

  test('a mode the textures cannot draw builds without the debounce', () {
    fakeAsync((async) {
      final svc = make()..setInputs(people: scene.people);
      svc.update(_blue);
      async.flushTimers();
      svc.update(const BackdropChange(mode: BackdropMode.blur));
      async.elapse(_ms);
      expect(svc.assets!.key.plates, 1);
    });
  });

  test('new rasters rebuild the matte; the old one shows meanwhile', () {
    fakeAsync((async) {
      final svc = make()..setInputs(people: scene.people);
      svc.update(_blue);
      async.flushTimers();
      final old = svc.assets;
      final hair = MaskRaster(4, 3, Uint8List(12));
      svc.setInputs(people: scene.people, hair: hair);
      expect(svc.assets, same(old));
      async.flushTimers();
      expect(svc.assets, isNot(same(old)));
      expect(baseBuilds, 2);
      svc.setInputs(); // rasters gone: off
      expect(svc.assets, isNull);
    });
  });

  test('image mode: a new image rebuilds, the same one does not', () {
    fakeAsync((async) {
      final img = testBackdropImage(64, 40);
      const b = BackdropChange(mode: BackdropMode.image, imageRef: 'r');
      final svc = make()..setInputs(people: scene.people, image: img);
      svc.update(b);
      async.flushTimers();
      final first = svc.assets!;
      expect(first.image, same(img));
      svc.setInputs(people: scene.people, image: img);
      async.flushTimers();
      expect(svc.assets, same(first));
      final next = testBackdropImage(64, 40);
      svc.setInputs(people: scene.people, image: next);
      async.flushTimers();
      expect(svc.assets!.image, same(next));
    });
  });

  test('assetsFor is exact and does not publish', () {
    fakeAsync((async) {
      final svc = make()..setInputs(people: scene.people);
      svc.update(_blue);
      async.flushTimers();
      BackdropAssets? got;
      svc.assetsFor(_blue.copyWith(color: 0xFF000000)).then((a) => got = a);
      async.flushMicrotasks();
      expect(got, same(svc.assets));
      svc.assetsFor(_blue.copyWith(feather: 5)).then((a) => got = a);
      async.flushMicrotasks();
      expect(got!.fits(_blue.copyWith(feather: 5), null), isTrue);
      expect(published.length, 1);
      BackdropAssets? off = svc.assets;
      svc.assetsFor(BackdropChange.none).then((a) => off = a);
      async.flushMicrotasks();
      expect(off, isNull);
    });
  });

  test('a failed matte build is retried on the next change', () {
    fakeAsync((async) {
      failBase = true;
      final errors = <Object>[];
      final svc = make()..setInputs(people: scene.people);
      runZonedGuarded(() {
        svc.update(_blue);
        async.flushTimers();
      }, (e, _) => errors.add(e));
      expect(errors, hasLength(1));
      expect(svc.assets, isNull);
      failBase = false;
      svc.update(_blue.copyWith(feather: 20));
      async.flushTimers();
      expect(svc.assets, isNotNull);
    });
  });
}
