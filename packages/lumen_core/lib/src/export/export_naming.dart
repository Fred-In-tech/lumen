import 'export_preset.dart';

final _forbidden = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

String _two(int v) => v.toString().padLeft(2, '0');

/// The base name (no extension) of an export of [original] from
/// [template]: `{name}` (original without extension), `{date}`
/// (yyyy-MM-dd of [date]), `{seq}` (1-based, zero padded to the batch
/// size, at least two digits) and `{preset}`. Characters that are not
/// allowed in file names become `_`; an empty result falls back to
/// `{name}`. Unknown `{tokens}` are kept as typed.
String exportBaseName(
  String template, {
  required String original,
  required DateTime date,
  required int seq,
  required int total,
  required String preset,
}) {
  final dot = original.lastIndexOf('.');
  final name = dot > 0 ? original.substring(0, dot) : original;
  final width = total.toString().length < 2 ? 2 : total.toString().length;
  final out = template
      .replaceAll('{name}', name)
      .replaceAll(
        '{date}',
        '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-'
            '${_two(date.day)}',
      )
      .replaceAll('{seq}', seq.toString().padLeft(width, '0'))
      .replaceAll('{preset}', preset)
      .replaceAll(_forbidden, '_')
      .trim();
  return out.isEmpty ? name.replaceAll(_forbidden, '_') : out;
}

/// [exportBaseName] plus the extension of [format].
String exportFileNameFor(
  String template, {
  required String original,
  required ExportFileFormat format,
  required DateTime date,
  required int seq,
  required int total,
  required String preset,
}) =>
    '${exportBaseName(template, original: original, date: date, seq: seq, total: total, preset: preset)}'
    '.${format.extension}';

/// [name], or `name (2).ext`, `name (3).ext` … when [taken] already has
/// it; the result is added to [taken].
String uniqueName(String name, Set<String> taken) {
  var out = name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var n = 2; taken.contains(out); n++) {
    out = '$base ($n)$ext';
  }
  taken.add(out);
  return out;
}
