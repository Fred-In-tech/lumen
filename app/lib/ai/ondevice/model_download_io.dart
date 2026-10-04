import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:lumen/ai/ondevice/model_store.dart';

final _contentRange = RegExp(r'^bytes (\d+)-');

/// Downloads [url] into [part], resuming from its current length with an
/// HTTP `Range` request. Returns null when [part] holds exactly
/// [expectedBytes] (hash not yet checked), else the error.
///
/// On a network failure or cancellation the partial file is kept for the
/// next resume; on an oversize response it is deleted. A server that
/// ignores the range (200) or answers 416 makes it start from zero once.
Future<ModelStoreError?> downloadResumable({
  required http.Client client,
  required Uri url,
  required File part,
  required int expectedBytes,
  CancelToken? cancel,
  void Function(int receivedBytes)? onProgress,
  Duration stallTimeout = const Duration(seconds: 30),
}) async {
  await part.parent.create(recursive: true);
  var restarted = false;
  while (true) {
    if (cancel?.isCancelled ?? false) return const ModelDownloadCancelled();
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > expectedBytes) {
      await part.delete();
      offset = 0;
    }
    if (offset == expectedBytes) return null;
    final req = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: cancel?.whenCancelled,
    );
    if (offset > 0) req.headers['range'] = 'bytes=$offset-';
    final http.StreamedResponse resp;
    try {
      resp = await client.send(req).timeout(stallTimeout);
    } on http.RequestAbortedException {
      return const ModelDownloadCancelled();
    } on http.ClientException catch (e) {
      return ModelDownloadFailed('connection failed: ${e.message}');
    } on TimeoutException {
      return const ModelDownloadFailed('server did not respond');
    }
    final status = resp.statusCode;
    final resumes =
        status == 206 &&
        _contentRange
                .firstMatch(resp.headers['content-range'] ?? '')
                ?.group(1) ==
            '$offset';
    if (status == 200 || resumes) {
      return _stream(
        resp,
        part,
        status == 200 ? 0 : offset,
        expectedBytes,
        cancel,
        onProgress,
        stallTimeout,
      );
    }
    unawaited(resp.stream.listen(null).cancel());
    if ((status == 206 || status == 416) && !restarted) {
      restarted = true;
      await part.delete();
      continue;
    }
    return ModelDownloadFailed('HTTP $status', statusCode: status);
  }
}

Future<ModelStoreError?> _stream(
  http.StreamedResponse resp,
  File part,
  int offset,
  int expectedBytes,
  CancelToken? cancel,
  void Function(int)? onProgress,
  Duration stallTimeout,
) async {
  final sink = part.openWrite(
    mode: offset == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend,
  );
  var received = offset;
  ModelStoreError? error;
  try {
    await for (final chunk in resp.stream.timeout(stallTimeout)) {
      if (cancel?.isCancelled ?? false) {
        error = const ModelDownloadCancelled();
        break;
      }
      received += chunk.length;
      if (received > expectedBytes) {
        error = ModelSizeMismatch(expected: expectedBytes, actual: received);
        break;
      }
      sink.add(chunk);
      onProgress?.call(received);
    }
  } on http.RequestAbortedException {
    error = const ModelDownloadCancelled();
  } on http.ClientException catch (e) {
    error = ModelDownloadFailed('interrupted: ${e.message}');
  } on IOException catch (e) {
    error = ModelDownloadFailed('interrupted: $e');
  } on TimeoutException {
    error = const ModelDownloadFailed('download stalled');
  } finally {
    await sink.flush();
    await sink.close();
  }
  if (error is ModelSizeMismatch) await part.delete();
  if (error == null && received != expectedBytes) {
    error = ModelDownloadFailed('connection closed at $received bytes');
  }
  return error;
}
