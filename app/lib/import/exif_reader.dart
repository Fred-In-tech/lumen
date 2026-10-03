import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

final _log = Logger('ExifReader');

/// Reads privacy-safe EXIF facts. GPS is never read into the model.
Future<ExifSummary> readExifSummary(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    if (tags.isEmpty) return const ExifSummary();
    String? s(String k) {
      final v = tags[k]?.printable.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    double? ratio(String k) {
      final t = tags[k];
      if (t == null) return null;
      final vals = t.values.toList();
      if (vals.isEmpty) return null;
      final v = vals.first;
      if (v is Ratio) return v.denominator == 0 ? null : v.numerator / v.denominator;
      if (v is num) return v.toDouble();
      return double.tryParse(t.printable);
    }

    final make = s('Image Make');
    final model = s('Image Model');
    final camera = model == null
        ? make
        : (make != null && !model.toLowerCase().startsWith(make.toLowerCase().split(' ').first))
            ? '$make $model'
            : model;
    final exposure = ratio('EXIF ExposureTime');
    final dt = s('EXIF DateTimeOriginal') ?? s('Image DateTime');
    return ExifSummary(
      camera: camera,
      lens: s('EXIF LensModel'),
      iso: int.tryParse(s('EXIF ISOSpeedRatings') ?? ''),
      shutter: s('EXIF ExposureTime'),
      exposureSeconds: exposure,
      aperture: ratio('EXIF FNumber'),
      focalMm: ratio('EXIF FocalLength'),
      capturedAt: _parseExifDate(dt),
      flash: s('EXIF Flash') == null ? null : !(s('EXIF Flash')!.toLowerCase().contains('no')),
      orientation: (tags['Image Orientation']?.values.firstAsInt()),
    );
  } on Exception catch (e) {
    _log.fine('EXIF read failed: $e');
    return const ExifSummary();
  }
}

DateTime? _parseExifDate(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(v);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  if (p[0] < 1900) return null;
  return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}
