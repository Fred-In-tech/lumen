/// Reports free disk space for the model download guard.
abstract interface class DiskSpaceProbe {
  /// Free bytes on the volume holding [path], or null when unknown (the
  /// store then proceeds with a logged warning).
  Future<int?> freeBytes(String path);
}

/// A fixed answer: mobile (no portable API without a plugin) and tests.
class FixedDiskSpaceProbe implements DiskSpaceProbe {
  const FixedDiskSpaceProbe(this.bytes);

  /// Always unknown.
  const FixedDiskSpaceProbe.unknown() : bytes = null;

  final int? bytes;

  @override
  Future<int?> freeBytes(String path) async => bytes;
}

final _dfRow = RegExp(r'\s(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%');

/// Available bytes from `df -Pk <path>` output (POSIX format, 1024-byte
/// blocks; same columns on macOS and Linux). Null when unparseable.
int? parseDfAvailableBytes(String stdout) {
  final lines = stdout.trim().split('\n');
  if (lines.length < 2) return null;
  final m = _dfRow.firstMatch(lines.last);
  final kb = m == null ? null : int.tryParse(m.group(3)!);
  return kb == null ? null : kb * 1024;
}

/// Free bytes from `(Get-PSDrive -Name C).Free` output.
int? parsePowerShellFreeBytes(String stdout) => int.tryParse(stdout.trim());

/// Drive letter of a Windows path (`C:\…` → `C`), else null.
String? windowsDriveLetter(String path) {
  final m = RegExp(r'^([A-Za-z]):').firstMatch(path);
  return m?.group(1)?.toUpperCase();
}
