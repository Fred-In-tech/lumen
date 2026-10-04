import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/import/folder_expansion_io.dart';
import 'package:path/path.dart' as p;

void main() {
  test('dropped folders skip hidden files and Lumen-derived data', () async {
    final root = await Directory.systemTemp.createTemp('lumen_drop');
    addTearDown(() => root.delete(recursive: true));
    Future<void> touch(String rel) async {
      final f = File(p.join(root.path, rel));
      await f.parent.create(recursive: true);
      await f.writeAsBytes([0]);
    }

    await touch('shoot/a.jpg');
    await touch('shoot/day2/b.png');
    await touch('shoot/.hidden.jpg');
    await touch('shoot/.thumbs/c.jpg');
    await touch('library/assets/x1/original.jpg');
    await touch('library/assets/x1/cache/region.png');
    await touch('library/assets/x1/retouch/h3.png');
    await touch('notes.txt');

    final out = await expandFolders([XFile(root.path)]);
    final names = out.map((f) => p.relative(f.path, from: root.path)).toSet();
    expect(names, {
      p.join('shoot', 'a.jpg'),
      p.join('shoot', 'day2', 'b.png'),
      p.join('library', 'assets', 'x1', 'original.jpg'),
    });
  });
}
