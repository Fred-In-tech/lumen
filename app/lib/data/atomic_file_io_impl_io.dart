import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] to [path] atomically: temp file, flush, rename.
///
/// On Windows a rename onto an existing file can fail; we then delete the
/// target and retry.
Future<void> atomicWrite(String path, Uint8List bytes) async {
  final target = File(path);
  await target.parent.create(recursive: true);
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  try {
    await tmp.rename(path);
  } on FileSystemException {
    if (await target.exists()) await target.delete();
    await tmp.rename(path);
  }
}
