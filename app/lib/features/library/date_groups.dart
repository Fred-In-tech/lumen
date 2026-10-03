import 'package:lumen_core/lumen_core.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday", "Sep 28" (this year) or "Sep 28, 2025".
String dayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? base : '$base, ${d.year}';
}

/// Groups entries (already sorted newest first) by local calendar day.
List<({String label, List<CatalogEntry> entries})> groupByDay(List<CatalogEntry> entries, DateTime now) {
  final groups = <({String label, List<CatalogEntry> entries})>[];
  DateTime? current;
  var bucket = <CatalogEntry>[];
  for (final e in entries) {
    final local = e.sortDate.isUtc ? e.sortDate.toLocal() : e.sortDate;
    final day = DateTime(local.year, local.month, local.day);
    if (current != day) {
      if (current != null) groups.add((label: dayLabel(current, now), entries: List.unmodifiable(bucket)));
      current = day;
      bucket = [];
    }
    bucket.add(e);
  }
  if (current != null) groups.add((label: dayLabel(current, now), entries: List.unmodifiable(bucket)));
  return groups;
}
