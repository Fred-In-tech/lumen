import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/import/import_file.dart';

/// Where imported files come from. Swapped for a fake in tests.
abstract interface class ImportSource {
  /// Opens the platform picker. Returns an empty list when cancelled.
  Future<List<ImportFile>> pick({required bool mobile});
}

class PickerImportSource implements ImportSource {
  const PickerImportSource();

  @override
  Future<List<ImportFile>> pick({required bool mobile}) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose photos',
      type: mobile ? FileType.image : FileType.custom,
      allowedExtensions: mobile ? null : kImportExtensions,
    );
    return readXFiles([for (final f in files) f.xFile]);
  }
}

/// Reads dropped or picked files, skipping anything without a photo extension.
Future<List<ImportFile>> readXFiles(List<XFile> files) async {
  final out = <ImportFile>[];
  for (final f in files) {
    final ext = p.extension(f.name).replaceFirst('.', '').toLowerCase();
    if (ext.isNotEmpty && !kImportExtensions.contains(ext)) continue;
    out.add(ImportFile(name: f.name, bytes: await f.readAsBytes()));
  }
  return out;
}
