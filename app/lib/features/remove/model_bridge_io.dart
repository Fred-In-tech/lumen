import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/remove/remove_jobs.dart';
import 'package:lumen/platform/cancellable_task.dart';

/// Runs a model removal with the pipeline's CPU work (context crops,
/// resampling, detail restoration, feathering) on a background isolate.
/// Only the `inpaint` calls come back to this isolate, where [model]'s
/// session lives (LiteRT runs it on its own helper isolate).
CancellableTask<InpaintResult> startModelRemoval(
  CancellableRunner run,
  HealInput input,
  InpaintModel model,
  InpaintConfig config,
) {
  final server = RawReceivePort();
  server.handler = (Object? message) {
    if (message case _Request(:final crop, :final keep, :final reply)) {
      model
          .inpaint(crop, keep)
          .then(reply.send, onError: (Object e) => reply.send('$e'));
    }
  };
  final task = _start(run, input, model.id, config, server.sendPort);
  unawaited(
    task.result.then<void>(
      (_) => server.close(),
      onError: (Object _) => server.close(),
    ),
  );
  return task;
}

CancellableTask<InpaintResult> _start(
  CancellableRunner run,
  HealInput input,
  String modelId,
  InpaintConfig config,
  SendPort server,
) => run(() {
  final source = input.healedBase();
  final hole = rasterizeHoleMask(input.strokes, source.width, source.height);
  return InpaintPipeline.remove(
    source,
    hole,
    model: _PortModel(modelId, server),
    method: InpaintMethod.model,
    config: config,
  );
});

class _Request {
  const _Request(this.crop, this.keep, this.reply);
  final RgbaBuffer crop;
  final Uint8List keep;
  final SendPort reply;
}

/// The worker's stand-in for the model: forwards each crop to the isolate
/// that owns the real one.
class _PortModel implements InpaintModel {
  const _PortModel(this.id, this._server);

  @override
  final String id;
  final SendPort _server;

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keep) async {
    final reply = ReceivePort();
    try {
      _server.send(_Request(crop, keep, reply.sendPort));
      final result = await reply.first;
      if (result is RgbaBuffer) return result;
      throw StateError('AI fill failed: $result');
    } finally {
      reply.close();
    }
  }
}
