import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/export/export_service.dart';

final _log = Logger('ExportBatch');

/// Writes one finished file; returns where it went (null: kept in memory,
/// e.g. the web download).
typedef ExportWriter = Future<String?> Function(ExportedFile file);

/// One photo that could not be exported.
class ExportFailure {
  const ExportFailure(this.assetId, this.name, this.reason);
  final String assetId;

  /// The photo's file name (or its id when the catalog has none).
  final String name;

  /// Why, in words for the user.
  final String reason;
}

/// Outcome of a batch.
class ExportBatchResult {
  const ExportBatchResult({
    required this.written,
    required this.failures,
    required this.notes,
    required this.cancelled,
    required this.total,
  });

  /// Paths (or file names when nothing was written to disk) of the files.
  final List<String> written;
  final List<ExportFailure> failures;

  /// What exports had to leave out (portrait retouch without analysis).
  final List<String> notes;
  final bool cancelled;
  final int total;
}

/// Progress of a running batch: [done] of [total] photos finished,
/// [current] the file name being exported (null when finished).
typedef ExportProgress = void Function(int done, int total, String? current);

Future<void> _lane = Future.value();

/// Runs [job] after every export started before it (app-wide): one
/// full-resolution export in flight at a time, so a 45 MP float export
/// never shares memory with another one.
Future<T> serialExport<T>(Future<T> Function() job) {
  final run = _lane.then((_) => job());
  _lane = run.then<void>((_) {}, onError: (Object _) {});
  return run;
}

/// Exports photos one at a time with one set of options: progress after
/// each, cancel between photos, a failure never stops the batch.
class ExportBatch {
  const ExportBatch(this.service, this.write, {this.catalog});

  final ExportService service;
  final ExportWriter write;

  /// For readable names in failures (null: asset ids).
  final CatalogRepository? catalog;

  Future<ExportBatchResult> run(
    List<String> assetIds,
    ExportOptions options, {
    bool Function()? isCancelled,
    ExportProgress? onProgress,
  }) async {
    final written = <String>[];
    final failures = <ExportFailure>[];
    final notes = <String>[];
    final taken = <String>{};
    final exported = <String>[];
    final total = assetIds.length;
    var cancelled = false;
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final id = assetIds[i];
      final name = await _nameOf(id);
      onProgress?.call(i, total, name);
      try {
        final file = await serialExport(
          () => service.exportOne(id, options, seq: i + 1, total: total),
        );
        final unique = file.renamed(uniqueName(file.fileName, taken));
        written.add(await write(unique) ?? unique.fileName);
        exported.add(id);
        if (file.note != null) notes.add(file.note!);
      } on Exception catch (e) {
        _log.warning('export of $id failed: $e');
        failures.add(ExportFailure(id, name, describeExportError(e)));
      }
    }
    await _stamp(exported);
    onProgress?.call(written.length + failures.length, total, null);
    return ExportBatchResult(
      written: written,
      failures: failures,
      notes: notes,
      cancelled: cancelled,
      total: total,
    );
  }

  /// Records the export on the photos (project progress reads it). A
  /// failure here never fails the export itself.
  Future<void> _stamp(List<String> ids) async {
    final repo = catalog;
    if (repo == null || ids.isEmpty) return;
    try {
      await repo.markExported(ids, DateTime.now().toUtc());
    } on Exception catch (e) {
      _log.warning('could not record the export: $e');
    }
  }

  Future<String> _nameOf(String id) async {
    try {
      return (await catalog?.get(id))?.fileName ?? id;
    } on Exception {
      return id;
    }
  }
}

/// A short, user-facing reason for an export failure.
String describeExportError(Exception e) {
  final text = switch (e) {
    CatalogException(:final message) => message,
    _ => e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), ''),
  };
  final line = text.split('\n').first.trim();
  return line.isEmpty ? 'Unknown error' : line;
}
