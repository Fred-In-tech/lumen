import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumen/ai/ondevice/disk_space_probe.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/ai/ondevice/model_store_io.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

/// Serves [body] on 127.0.0.1 with Range support and scripted faults.
class _Server {
  _Server(this.body);

  Uint8List body;
  late HttpServer _server;
  final List<String?> ranges = [];

  /// Next request: send this many bytes, then drop the connection.
  int? cutAfter;
  bool ignoreRange = false;
  Duration? chunkDelay;

  Uri url(String file) => Uri.parse('http://127.0.0.1:${_server.port}/$file');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final range = req.headers.value('range');
    ranges.add(range);
    final res = req.response;
    var start = 0;
    final m = RegExp(r'bytes=(\d+)-').firstMatch(range ?? '');
    if (m != null && !ignoreRange) {
      start = int.parse(m.group(1)!);
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        'content-range',
        'bytes $start-${body.length - 1}/${body.length}',
      );
    }
    final slice = body.sublist(start);
    res.contentLength = slice.length;
    try {
      final cut = cutAfter;
      if (cut != null) {
        cutAfter = null;
        final socket = await res.detachSocket();
        socket.add(slice.sublist(0, cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      final delay = chunkDelay;
      if (delay == null) {
        res.add(slice);
      } else {
        for (var i = 0; i < slice.length; i += 1024) {
          res.add(
            slice.sublist(i, i + 1024 > slice.length ? slice.length : i + 1024),
          );
          await res.flush();
          await Future<void>.delayed(delay);
        }
      }
      await res.close();
    } on IOException {
      // The client went away (cancellation tests).
    }
  }
}

Uint8List _bytes(int n, [int seed = 1]) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + seed) & 0xff]);

String _sha(List<int> b) => sha256.convert(b).toString();

ModelSpec _spec(
  String id,
  Uri url,
  Uint8List body, {
  String? sha,
  bool bundled = false,
  int? bytes,
  String? disabled,
}) => ModelSpec(
  id: id,
  version: '1',
  fileName: '$id.tflite',
  url: url.toString(),
  bytes: bytes ?? body.length,
  sha256: sha ?? _sha(body),
  license: 'test',
  trainingDataNote: 'test',
  bundled: bundled,
  disabledReason: disabled,
);

void main() {
  late Directory tmp;
  late _Server server;
  late http.Client client;
  final body = _bytes(64 * 1024);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('model_store_test');
    server = _Server(body);
    await server.start();
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.close();
    await tmp.delete(recursive: true);
  });

  FileModelStore store({
    DiskSpaceProbe probe = const FixedDiskSpaceProbe(1 << 40),
    int budget = 1 << 30,
    List<ModelSpec> manifest = const [],
    BundledModelLoader? bundled,
    DateTime Function()? clock,
  }) => FileModelStore(
    root: p.join(tmp.path, 'models'),
    client: client,
    diskProbe: probe,
    budgetBytes: budget,
    manifest: manifest,
    bundled: bundled,
    clock: clock,
  );

  test('full download: verified, renamed, reported, then reused', () async {
    final s = store();
    final spec = _spec('a', server.url('a'), body);
    final events = <ModelProgress>[];
    final sub = s.progress.listen(events.add);

    final r = await s.ensure(spec);

    expect(r, isA<ModelReady>());
    final path = (r as ModelReady).path;
    expect(path, s.pathFor(spec));
    expect(await File(path).readAsBytes(), body);
    expect(File('$path.part').existsSync(), isFalse);
    await pumpEventQueue();
    expect(events.first.phase, ModelPhase.checking);
    expect(events.any((e) => e.phase == ModelPhase.downloading), isTrue);
    expect(events.last.phase, ModelPhase.ready);
    expect(events.last.fraction, 1);
    // Second call: no network, same path.
    expect(await s.ensure(spec), isA<ModelReady>());
    expect(await s.readyPath(spec), path);
    expect(server.ranges, hasLength(1));
    await sub.cancel();
  });

  test('resumes with a Range request after an interrupted transfer', () async {
    final s = store();
    final spec = _spec('a', server.url('a'), body);
    server.cutAfter = 20000;

    final first = await s.ensure(spec);

    expect(
      first,
      isA<ModelFailed>().having(
        (f) => f.error,
        'error',
        isA<ModelDownloadFailed>(),
      ),
    );
    final part = File('${s.pathFor(spec)}.part');
    final kept = part.lengthSync();
    expect(kept, inInclusiveRange(1, 20000));
    expect(await s.readyPath(spec), isNull);

    final second = await s.ensure(spec);

    expect(second, isA<ModelReady>());
    expect(server.ranges.last, 'bytes=$kept-');
    expect(await File(s.pathFor(spec)).readAsBytes(), body);
  });

  test('a server that ignores Range restarts from zero', () async {
    final s = store();
    final spec = _spec('a', server.url('a'), body);
    server.cutAfter = 5000;
    await s.ensure(spec);
    server.ignoreRange = true;
    expect(await s.ensure(spec), isA<ModelReady>());
    expect(await File(s.pathFor(spec)).readAsBytes(), body);
  });

  test('SHA mismatch deletes the file and reports a typed error', () async {
    final s = store();
    final spec = _spec('a', server.url('a'), body, sha: _sha([1, 2, 3]));
    final r = await s.ensure(spec);
    expect(
      r,
      isA<ModelFailed>().having(
        (f) => f.error,
        'error',
        isA<ModelChecksumMismatch>().having(
          (e) => e.actual,
          'actual',
          _sha(body),
        ),
      ),
    );
    expect(File(s.pathFor(spec)).existsSync(), isFalse);
    expect(File('${s.pathFor(spec)}.part').existsSync(), isFalse);
  });

  test('oversize responses are cut off and deleted', () async {
    final s = store();
    final spec = _spec('a', server.url('a'), body, bytes: 1000);
    final r = await s.ensure(spec) as ModelFailed;
    expect(r.error, isA<ModelSizeMismatch>());
    expect(File('${s.pathFor(spec)}.part').existsSync(), isFalse);
  });

  test('disk guard refuses before any request', () async {
    final s = store(probe: const FixedDiskSpaceProbe(200 * 1024 * 1024));
    final r = await s.ensure(_spec('a', server.url('a'), body)) as ModelFailed;
    final e = r.error as InsufficientDiskSpace;
    expect(e.requiredBytes, 2 * body.length + 200 * 1024 * 1024);
    expect(e.availableBytes, 200 * 1024 * 1024);
    expect(server.ranges, isEmpty);
    // Unknown free space (mobile) proceeds.
    final s2 = store(probe: const FixedDiskSpaceProbe.unknown());
    expect(
      await s2.ensure(_spec('a', server.url('a'), body)),
      isA<ModelReady>(),
    );
  });

  test('unpinned and disabled specs are refused without a request', () async {
    final s = store();
    final unpinned = ModelSpec(
      id: 'u',
      version: '1',
      fileName: 'u.tflite',
      url: server.url('u').toString(),
      bytes: body.length,
      license: '-',
      trainingDataNote: '-',
    );
    final r1 = await s.ensure(unpinned) as ModelFailed;
    expect((r1.error as ModelRefused).cause, isA<UnpinnedModelException>());
    final r2 = await s.ensure(
      _spec('d', server.url('d'), body, disabled: 'ops'),
    ) as ModelFailed;
    expect((r2.error as ModelRefused).cause, isA<DisabledModelException>());
    expect(server.ranges, isEmpty);
    expect(await s.readyPath(unpinned), isNull);
  });

  test('LRU eviction keeps recently used models under the budget', () async {
    var t = 0;
    final s = store(
      budget: (body.length * 2.5).round(),
      clock: () => DateTime(2026, 1, 1, 0, ++t),
    );
    final a = _spec('a', server.url('a'), body);
    final b = _spec('b', server.url('b'), body);
    final c = _spec('c', server.url('c'), body);
    await s.ensure(a); // t1
    await s.ensure(b); // t2
    await s.ensure(a); // t3: a is now more recent than b
    expect(await s.ensure(c), isA<ModelReady>()); // evicts b
    expect(File(s.pathFor(a)).existsSync(), isTrue);
    expect(File(s.pathFor(b)).existsSync(), isFalse);
    expect(File(s.pathFor(c)).existsSync(), isTrue);
  });

  test('bundled models: verified extraction, never evicted', () async {
    final asset = _bytes(4096, 7);
    final bundledSpec = _spec('bund', server.url('-'), asset, bundled: true);
    final s = store(
      manifest: [bundledSpec],
      budget: 1,
      bundled: (key) async => key == bundledSpec.bundledAssetKey ? asset : null,
    );
    final r = await s.ensure(bundledSpec) as ModelReady;
    expect(await File(r.path).readAsBytes(), asset);
    await s.evictToBudget();
    expect(File(r.path).existsSync(), isTrue);
    expect(server.ranges, isEmpty);

    final tampered = store(bundled: (_) async => _bytes(4096, 8));
    final bad = _spec('bund2', server.url('-'), asset, bundled: true);
    expect(
      ((await tampered.ensure(bad)) as ModelFailed).error,
      isA<ModelChecksumMismatch>(),
    );
    final missing = store(bundled: (_) async => null);
    final bad2 = _spec('bund3', server.url('-'), asset, bundled: true);
    expect(
      ((await missing.ensure(bad2)) as ModelFailed).error,
      isA<BundledModelMissing>(),
    );
  });

  test(
    'cancellation stops the transfer and keeps the part for resume',
    () async {
      final s = store();
      final spec = _spec('a', server.url('a'), body);
      server.chunkDelay = const Duration(milliseconds: 15);
      final token = CancelToken();
      final sub = s.progress.listen((e) {
        if (e.phase == ModelPhase.downloading) token.cancel();
      });

      final r = await s.ensure(spec, cancel: token);

      expect((r as ModelFailed).error, isA<ModelDownloadCancelled>());
      expect(File(s.pathFor(spec)).existsSync(), isFalse);
      final kept = File('${s.pathFor(spec)}.part').lengthSync();
      expect(kept, lessThan(body.length));
      await sub.cancel();

      server.chunkDelay = null;
      expect(await s.ensure(spec), isA<ModelReady>());
      if (kept > 0) expect(server.ranges.last, 'bytes=$kept-');
    },
  );

  test('concurrent ensure calls share one download', () async {
    final s = store();
    final spec = _spec('a', server.url('a'), body);
    final results = await Future.wait([s.ensure(spec), s.ensure(spec)]);
    expect(results.every((r) => r is ModelReady), isTrue);
    expect(server.ranges, hasLength(1));
  });

  test('a corrupted file on disk is re-verified and deleted', () async {
    final spec = _spec('a', server.url('a'), body);
    final path = ((await store().ensure(spec)) as ModelReady).path;
    final tampered = Uint8List.fromList(body)..[100] ^= 0xff;
    await File(path).writeAsBytes(tampered);
    // A new session hashes again before handing out the path.
    final fresh = store();
    expect(await fresh.readyPath(spec), isNull);
    expect(File(path).existsSync(), isFalse);
  });
}
