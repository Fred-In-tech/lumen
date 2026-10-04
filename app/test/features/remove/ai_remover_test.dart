import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/features/remove/ai_remover.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen_core/lumen_core.dart';

class _Model implements InpaintModel {
  @override
  String get id => 'fake@1';

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keep) async => crop;
}

class _Loader implements AiRemoverLoader {
  _Loader({this.installed = false, this.error});

  final bool installed;
  final Object? error;
  final Completer<void> gate = Completer<void>();
  int loads = 0;
  CancelToken? lastCancel;

  @override
  int get downloadBytes => 16312640;

  @override
  Future<bool> isInstalled() async => installed;

  @override
  Future<InpaintModel> load({
    required void Function(double? fraction) onProgress,
    CancelToken? cancel,
  }) async {
    loads++;
    lastCancel = cancel;
    onProgress(0.5);
    await Future.any([gate.future, cancel!.whenCancelled]);
    if (cancel.isCancelled) throw const ModelDownloadCancelled();
    final e = error;
    if (e != null) throw e;
    return _Model();
  }
}

ProviderContainer _container(_Loader loader) {
  final c = ProviderContainer(
    overrides: [aiRemoverLoaderProvider.overrideWithValue(loader)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('off by default: probing never downloads', () async {
    final loader = _Loader();
    final c = _container(loader);
    await c.read(aiRemoverProvider.notifier).probe();
    expect(c.read(aiRemoverProvider).phase, AiRemoverPhase.off);
    expect(loader.loads, 0);
    expect(c.read(removeModelProvider), isNull);
    expect(megabytes(loader.downloadBytes), '16 MB');
  });

  test(
    'switching on downloads with progress, then supplies the model',
    () async {
      final loader = _Loader();
      final c = _container(loader);
      final done = c.read(aiRemoverProvider.notifier).enable();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(aiRemoverProvider).phase, AiRemoverPhase.downloading);
      expect(c.read(aiRemoverProvider).progress, 0.5);
      loader.gate.complete();
      await done;
      expect(c.read(aiRemoverProvider).usable, isTrue);
      expect(c.read(removeModelProvider)?.id, 'fake@1');
      c.read(aiRemoverProvider.notifier).disable();
      expect(c.read(removeModelProvider), isNull, reason: 'classic only');
    },
  );

  test('an earlier download is loaded and switched on by the probe', () async {
    final loader = _Loader(installed: true)..gate.complete();
    final c = _container(loader);
    await c.read(aiRemoverProvider.notifier).probe();
    expect(c.read(aiRemoverProvider).usable, isTrue);
  });

  test('failures leave classic fill with an honest message', () async {
    final loader = _Loader(
      error: const ModelDownloadFailed('HTTP 503', statusCode: 503),
    )..gate.complete();
    final c = _container(loader);
    await c.read(aiRemoverProvider.notifier).enable();
    final s = c.read(aiRemoverProvider);
    expect(s.phase, AiRemoverPhase.failed);
    expect(s.message, contains('Classic fill is used'));
    expect(c.read(removeModelProvider), isNull);

    final none = _Loader(error: const InferenceUnavailable('web'))
      ..gate.complete();
    final c2 = _container(none);
    await c2.read(aiRemoverProvider.notifier).enable();
    expect(c2.read(aiRemoverProvider).phase, AiRemoverPhase.unavailable);
  });

  test('cancelling the download turns AI fill back off', () async {
    final loader = _Loader();
    final c = _container(loader);
    final done = c.read(aiRemoverProvider.notifier).enable();
    await Future<void>.delayed(Duration.zero);
    c.read(aiRemoverProvider.notifier).cancelDownload();
    await done;
    expect(c.read(aiRemoverProvider).phase, AiRemoverPhase.off);
    expect(c.read(aiRemoverProvider).enabled, isFalse);
  });
}
