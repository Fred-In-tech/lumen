import 'package:lumen_core/lumen_core.dart';

/// One titled block of the photo info panel.
typedef InfoSection = ({String title, List<(String, String)> rows});

const _formatNames = {
  'jpeg': 'JPEG',
  'png': 'PNG',
  'webp': 'WebP',
  'heic': 'HEIC',
  'cr2': 'Canon RAW (CR2)',
  'cr3': 'Canon RAW (CR3)',
  'dng': 'Digital Negative (DNG)',
  'nef': 'Nikon RAW (NEF)',
  'nrw': 'Nikon RAW (NRW)',
  'arw': 'Sony RAW (ARW)',
  'sr2': 'Sony RAW (SR2)',
  'raf': 'Fujifilm RAW (RAF)',
  'orf': 'Olympus RAW (ORF)',
  'rw2': 'Panasonic RAW (RW2)',
  'pef': 'Pentax RAW (PEF)',
  'srw': 'Samsung RAW (SRW)',
  'erf': 'Epson RAW (ERF)',
  'threeFr': 'Hasselblad RAW (3FR)',
};

/// "Canon RAW (CR3)" for a catalog format id.
String formatLabel(String format) =>
    _formatNames[format] ?? format.toUpperCase();

/// "12.4 MB", "830 KB".
String fileSizeLabel(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).round()} KB';
  return '$bytes bytes';
}

String _two(int v) => v.toString().padLeft(2, '0');

String _date(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

String _trim(double v, {int decimals = 1}) {
  final s = v.toStringAsFixed(decimals);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Everything known about [e], grouped for the info panel. Rows without a
/// value are left out, and so are sections without rows. GPS and serial
/// numbers are never stored, so they can never appear here.
List<InfoSection> photoInfo(CatalogEntry e) {
  final x = e.exif;
  final mp = e.width * e.height / 1e6;
  final bias = x.exposureBias;
  final sections = <InfoSection>[
    (
      title: 'File',
      rows: [
        ('Name', e.fileName),
        ('Type', formatLabel(e.format)),
        if (e.width > 0 && e.height > 0)
          ('Size', '${e.width} × ${e.height}  (${_trim(mp)} MP)'),
        if (e.bytes > 0) ('File size', fileSizeLabel(e.bytes)),
        ('Imported', _date(e.importedAt.toLocal())),
      ],
    ),
    (
      title: 'Camera',
      rows: [
        if (x.camera != null) ('Camera', x.camera!),
        if (x.lens != null) ('Lens', x.lens!),
        if (x.capturedAt != null) ('Taken', _date(x.capturedAt!)),
        if (x.software != null) ('Software', x.software!),
      ],
    ),
    (
      title: 'Exposure',
      rows: [
        if (x.shutter != null) ('Shutter', '${x.shutter} s'),
        if (x.aperture != null) ('Aperture', 'f/${_trim(x.aperture!)}'),
        if (x.iso != null) ('ISO', '${x.iso}'),
        if (x.focalMm != null) ('Focal length', '${_trim(x.focalMm!)} mm'),
        if (bias != null)
          (
            'Exposure comp.',
            '${bias > 0 ? '+' : (bias < 0 ? '−' : '')}'
                '${_trim(bias.abs(), decimals: 2)} EV',
          ),
        if (x.program != null) ('Program', x.program!),
        if (x.metering != null) ('Metering', x.metering!),
        if (x.whiteBalance != null) ('White balance', x.whiteBalance!),
        if (x.flash != null) ('Flash', x.flash! ? 'Fired' : 'Did not fire'),
        if (x.colorSpace != null) ('Colour space', x.colorSpace!),
      ],
    ),
  ];
  return [
    for (final s in sections)
      if (s.rows.isNotEmpty) s,
  ];
}
