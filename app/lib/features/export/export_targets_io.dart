import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lumen/features/export/export_service.dart';

/// Asks for a destination folder (desktop), opening at [initial] (a
/// preset's folder; the sandbox only lets the app write where the user
/// picked). Null when cancelled.
Future<String?> chooseExportFolder({String? initial}) =>
    FilePicker.getDirectoryPath(
      dialogTitle: 'Export to folder',
      initialDirectory: initial,
    );

/// Writes [files] into [folder], never overwriting (adds " (2)" etc.).
/// Chunked files (16-bit TIFF) are streamed chunk by chunk.
Future<List<String>> writeExports(
  String folder,
  List<ExportedFile> files,
) async {
  final written = <String>[];
  for (final f in files) {
    var path = p.join(folder, f.fileName);
    var n = 2;
    while (await File(path).exists()) {
      path = p.join(
        folder,
        '${p.basenameWithoutExtension(f.fileName)} ($n)${p.extension(f.fileName)}',
      );
      n++;
    }
    final out = await File(path).open(mode: FileMode.writeOnly);
    try {
      for (final chunk in f.chunks) {
        await out.writeFrom(chunk);
      }
      await out.flush();
    } finally {
      await out.close();
    }
    written.add(path);
  }
  return written;
}

/// Mobile: a temporary folder the exports are written to before sharing.
Future<String> shareStagingFolder() async {
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'lumen_export'),
  );
  await dir.create(recursive: true);
  return dir.path;
}

/// Opens the share sheet for written files (Save to Photos lives there).
Future<void> sharePaths(List<String> paths) => SharePlus.instance.share(
  ShareParams(files: [for (final x in paths) XFile(x)]),
);

/// Mobile: saves to a temp folder and opens the share sheet.
Future<void> shareExports(List<ExportedFile> files) async {
  final paths = await writeExports(await shareStagingFolder(), files);
  await sharePaths(paths);
}

const bool kExportNeedsFolder = true;
