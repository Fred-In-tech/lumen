import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/import/import_file.dart';

/// Replaces dropped folders with the photos inside them (recursive, max [limit]).
Future<List<XFile>> expandFolders(List<XFile> items, {int limit = 2000}) async {
  final out = <XFile>[];
  for (final item in items) {
    final dir = Directory(item.path);
    if (item.path.isNotEmpty && await dir.exists()) {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (out.length >= limit) break;
        final ext = p.extension(e.path).replaceFirst('.', '').toLowerCase();
        if (e is File &&
            kImportExtensions.contains(ext) &&
            !p.basename(e.path).startsWith('.')) {
          out.add(XFile(e.path));
        }
      }
    } else {
      out.add(item);
    }
  }
  return out;
}
