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
  // Camera RAW: kept untouched as the original, developed once at import.
  cr2('cr2', isRaw: true),
  cr3('cr3', isRaw: true),
  dng('dng', isRaw: true),
  nef('nef', isRaw: true),
  arw('arw', isRaw: true),
  raf('raf', isRaw: true),
  unknown('bin');

  const PhotoFormat(this.extension, {this.isRaw = false});
  final String extension;

  /// Camera RAW needs the platform RAW developer before the engine can
  /// decode it (see `RawDeveloper`).
  final bool isRaw;

  bool get isSupported => this != unknown;
}

/// Sniffs the format from magic bytes (never trusts the file extension).
///
/// The one exception is TIFF-based RAW (DNG, NEF, ARW): those share the plain
/// TIFF header, so [fileName] picks between them once the header matches.
PhotoFormat sniffFormat(Uint8List b, {String? fileName}) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return PhotoFormat.jpeg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return PhotoFormat.png;
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 && //
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return PhotoFormat.webp;
  }
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    const heif = {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'mif1',
      'msf1',
      'heim',
      'heis',
      'avif',
    };
    if (heif.contains(brand)) return PhotoFormat.heic;
    if (brand == 'crx ') return PhotoFormat.cr3;
  }
  if (_isTiff(b)) {
    // Canon CR2 marks itself with "CR" right after the TIFF header.
    if (b.length >= 10 && b[8] == 0x43 && b[9] == 0x52) return PhotoFormat.cr2;
    final dot = fileName?.lastIndexOf('.') ?? -1;
    final ext = dot < 0 ? '' : fileName!.substring(dot + 1).toLowerCase();
    for (final f in const [PhotoFormat.dng, PhotoFormat.nef, PhotoFormat.arw]) {
      if (f.extension == ext) return f;
    }
  }
  if (b.length >= 15 &&
      String.fromCharCodes(b.sublist(0, 15)) == 'FUJIFILMCCD-RAW') {
    return PhotoFormat.raf;
  }
  return PhotoFormat.unknown;
}

/// Little- ("II*\0") or big-endian ("MM\0*") TIFF header.
bool _isTiff(Uint8List b) =>
    b.length >= 8 &&
    ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) ||
        (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A));

/// Camera RAW extensions (developed by the platform, Apple only for now).
const kRawExtensions = ['cr2', 'cr3', 'dng', 'nef', 'arw', 'raf'];

/// Accepted file extensions for the picker.
const kImportExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  ...kRawExtensions,
];
