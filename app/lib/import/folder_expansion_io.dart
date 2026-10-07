import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/import/import_file.dart';

/// Replaces dropped folders with the photos inside them (recursive, max
/// [limit]); [extensions] picks the files to keep (default: photos).
Future<List<XFile>> expandFolders(
  List<XFile> items, {
  int limit = 2000,
  List<String> extensions = kImportExtensions,
}) async {
  final out = <XFile>[];
  for (final item in items) {
    final dir = Directory(item.path);
    if (item.path.isNotEmpty && await dir.exists()) {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (out.length >= limit) break;
        final ext = p.extension(e.path).replaceFirst('.', '').toLowerCase();
        if (e is File &&
            extensions.contains(ext) &&
            !_isDerived(p.split(p.relative(e.path, from: dir.path)))) {
          out.add(XFile(e.path));
        }
      }
    } else {
      out.add(item);
    }
  }
  return out;
}

/// Hidden files/folders and Lumen's own derived data (face caches and heal
/// patches under `assets/<id>/`), so dropping a library folder never imports
/// private face maps or retouch patches as photos.
bool _isDerived(List<String> segments) {
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    if (s.startsWith('.')) return true;
    if (i < segments.length - 1 && (s == 'cache' || s == 'retouch')) {
      if (i >= 2 && segments[i - 2] == 'assets') return true;
      if (s == 'cache') return true;
    }
  }
  return false;
}
