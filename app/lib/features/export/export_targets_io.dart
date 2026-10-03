import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lumen/features/export/export_service.dart';

/// Asks for a destination folder (desktop). Null when cancelled.
Future<String?> chooseExportFolder() => FilePicker.getDirectoryPath(dialogTitle: 'Export to folder');

/// Writes [files] into [folder], never overwriting (adds " (2)" etc.).
Future<List<String>> writeExports(String folder, List<ExportedFile> files) async {
  final written = <String>[];
  for (final f in files) {
    var path = p.join(folder, f.fileName);
    var n = 2;
    while (await File(path).exists()) {
      path = p.join(folder, '${p.basenameWithoutExtension(f.fileName)} ($n)${p.extension(f.fileName)}');
      n++;
    }
    await File(path).writeAsBytes(f.bytes, flush: true);
    written.add(path);
  }
  return written;
}

/// Mobile: saves to a temp folder and opens the share sheet (Save to Photos lives there).
Future<void> shareExports(List<ExportedFile> files) async {
  final dir = await getTemporaryDirectory();
  final paths = await writeExports(dir.path, files);
  await SharePlus.instance.share(ShareParams(files: [for (final x in paths) XFile(x)]));
}

const bool kExportNeedsFolder = true;
