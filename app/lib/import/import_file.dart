import 'dart:typed_data';

/// A file chosen by the user (picker or drag-and-drop), already read into memory.
class ImportFile {
  const ImportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Image container formats we accept.
enum PhotoFormat {
  jpeg('jpg'),
  png('png'),
  webp('webp'),
  heic('heic'),
  unknown('bin');

  const PhotoFormat(this.extension);
  final String extension;

  bool get isSupported => this != unknown;
}

/// Sniffs the format from magic bytes (never trusts the file extension).
PhotoFormat sniffFormat(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return PhotoFormat.jpeg;
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return PhotoFormat.png;
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && //
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return PhotoFormat.webp;
  }
  if (b.length >= 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    const heif = {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heim', 'heis', 'avif'};
    if (heif.contains(brand)) return PhotoFormat.heic;
  }
  return PhotoFormat.unknown;
}

/// Accepted file extensions for the picker.
const kImportExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];
