import '../model/catalog_entry.dart';

/// Photos imported, edited and exported in a window (Home "This week").
class WeekStats {
  const WeekStats({
    required this.imported,
    required this.edited,
    required this.exported,
  });

  final int imported;
  final int edited;
  final int exported;
}

/// Counts over [entries] for the [window] ending at [now] (default: the
/// last 7 days). Edited counts photos whose current edit was saved in the
/// window; exported, photos last exported in it.
WeekStats weekStats(
  Iterable<CatalogEntry> entries,
  DateTime now, {
  Duration window = const Duration(days: 7),
}) {
  final from = now.subtract(window);
  bool inWindow(DateTime? t) => t != null && t.isAfter(from) && !t.isAfter(now);
  var imported = 0, edited = 0, exported = 0;
  for (final e in entries) {
    if (inWindow(e.importedAt)) imported++;
    if (e.hasEdits && inWindow(e.editedAt)) edited++;
    if (inWindow(e.exportedAt)) exported++;
  }
  return WeekStats(imported: imported, edited: edited, exported: exported);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "12 Oct 2026" (local calendar day of [d]).
String formatShootDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// A name for a new shoot: its capture day and first file, e.g.
/// "12 Oct 2026 · IMG_4021". Falls back to [now] without a capture date,
/// and to "`day` shoot" without a file name.
String suggestProjectName({
  required DateTime now,
  DateTime? capturedAt,
  String? firstFileName,
}) {
  final day = formatShootDate(capturedAt ?? now);
  final name = firstFileName?.trim() ?? '';
  final dot = name.lastIndexOf('.');
  final stem = (dot > 0 ? name.substring(0, dot) : name).trim();
  return stem.isEmpty ? '$day shoot' : '$day · $stem';
}
