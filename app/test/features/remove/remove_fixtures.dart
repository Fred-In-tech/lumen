import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/features/remove/remove_status.dart';
import 'package:lumen/platform/cancellable_task.dart';
import 'package:lumen_core/lumen_core.dart';

const kW = 160, kH = 120;

/// Square "object" to remove: x 60..89, y 40..69.
const kObject = PixelBox(60, 40, 30, 30);

/// Warm textured backdrop with a near-black square [kObject].
RgbaBuffer syntheticPhoto() {
  final b = RgbaBuffer(kW, kH);
  var s = 7;
  for (var y = 0; y < kH; y++) {
    for (var x = 0; x < kW; x++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final n = (s >> 16) % 9 - 4;
      final inObject =
          x >= kObject.x &&
          x < kObject.right &&
          y >= kObject.y &&
          y < kObject.bottom;
      if (inObject) {
        b.setPixel(x, y, 12, 10, 14);
      } else {
        b.setPixel(
          x,
          y,
          (150 + x ~/ 8 + n).clamp(0, 255),
          (120 + y ~/ 6 + n).clamp(0, 255),
          (90 + n).clamp(0, 255),
        );
      }
    }
  }
  return b;
}

/// One hard round stroke covering [kObject] (radius 24 px).
final kObjectStroke = [
  BrushStroke(
    points: [((kObject.x + 15) / kW, (kObject.y + 15) / kH)],
    radius: 24 / kW,
    hardness: 1,
  ),
];

/// Runs every task inline (no isolates), recording each one.
class InlineRunner {
  final List<TestTask<Object?>> tasks = [];

  /// Tasks with these indices never finish until cancelled.
  final Set<int> hang = {};

  CancellableTask<R> call<R>(FutureOr<R> Function() fn) {
    final task = TestTask<R>(hang.contains(tasks.length) ? null : fn);
    tasks.add(task);
    return task;
  }
}

class TestTask<R> implements CancellableTask<R> {
  TestTask(FutureOr<R> Function()? fn) {
    if (fn != null) {
      Future<R>(fn).then(
        (v) => _done.isCompleted ? null : _done.complete(v),
        onError: (Object e, StackTrace st) =>
            _done.isCompleted ? null : _done.completeError(e, st),
      );
    }
  }

  final Completer<R> _done = Completer<R>();
  bool _cancelled = false;

  @override
  Future<R> get result => _done.future;

  @override
  bool get isCancelled => _cancelled;

  @override
  void cancel() {
    _cancelled = true;
    if (!_done.isCompleted) _done.completeError(const InpaintCancelled());
  }
}

class RemoveHarness {
  RemoveHarness._(this.container, this.catalog, this.store, this.statuses);

  final ProviderContainer container;
  final MemoryCatalogRepository catalog;
  final MemoryPatchStore store;
  final List<RemoveStatus> statuses;

  static Future<RemoveHarness> create({
    SourceLoader? loader,
    CancellableRunner? runner,
    InpaintModel? model,
    List<Override> overrides = const [],
  }) async {
    final catalog = MemoryCatalogRepository();
    await catalog.add(
      CatalogEntry(
        assetId: 'a',
        fileName: 'a.jpg',
        originalPath: 'originals/a.jpg',
        format: 'jpeg',
        width: kW,
        height: kH,
        bytes: 1,
        importedAt: DateTime.utc(2026),
      ),
      Uint8List(1),
    );
    final store = MemoryPatchStore();
    final c = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(catalog),
        patchStoreProvider.overrideWith((ref) async => store),
        removeSourceLoaderProvider.overrideWithValue(
          loader ?? (_) async => syntheticPhoto(),
        ),
        if (runner != null) cancellableRunnerProvider.overrideWithValue(runner),
        if (model != null) removeModelProvider.overrideWithValue(model),
        ...overrides,
      ],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider('a').future);
    final statuses = <RemoveStatus>[];
    c.listen(removeStatusProvider('a'), (_, s) => statuses.add(s));
    return RemoveHarness._(c, catalog, store, statuses);
  }

  EditorState get editor => container.read(editorProvider('a')).value!;

  RemoveStatus get status => container.read(removeStatusProvider('a'));

  /// Polls until [ok] holds (fails after ~5 s).
  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 500 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ok(), isTrue, reason: 'condition never held');
  }

  /// The source with the current heal ops composited from the store.
  Future<RgbaBuffer> healed() async {
    final ops = editor.settings.heal;
    final patches = {
      for (final op in ops) op.patch: (await store.load('a', op.patch))!,
    };
    return composeHealed(syntheticPhoto(), ops, MapPatchLookup(patches));
  }
}

/// Mean luma of [box] in [b].
double meanLuma(RgbaBuffer b, PixelBox box) {
  var sum = 0.0;
  for (var y = box.y; y < box.bottom; y++) {
    for (var x = box.x; x < box.right; x++) {
      final o = b.offset(x, y);
      sum += 0.299 * b.data[o] + 0.587 * b.data[o + 1] + 0.114 * b.data[o + 2];
    }
  }
  return sum / box.area;
}
