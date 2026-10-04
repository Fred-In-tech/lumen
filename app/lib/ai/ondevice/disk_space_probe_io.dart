import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/ai/ondevice/disk_space_probe.dart';
import 'package:lumen/platform/platform_info.dart';

final _log = Logger('DiskSpaceProbe');

/// Runs a command; injectable for tests.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> args,
);

Future<ProcessResult> _run(String exe, List<String> args) =>
    Process.run(exe, args);

/// macOS/Linux: `df -Pk`; Windows: PowerShell `Get-PSDrive`; mobile: null.
class ProcessDiskSpaceProbe implements DiskSpaceProbe {
  ProcessDiskSpaceProbe(this.platform, {ProcessRunner? run})
    : _runner = run ?? _run;

  final PlatformInfo platform;
  final ProcessRunner _runner;

  @override
  Future<int?> freeBytes(String path) async {
    if (platform.isMobile || platform.isWeb) return null;
    try {
      if (platform.isWindows) {
        final drive = windowsDriveLetter(path);
        if (drive == null) return null;
        final r = await _runner('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-PSDrive -Name $drive).Free',
        ]);
        return r.exitCode == 0 ? parsePowerShellFreeBytes('${r.stdout}') : null;
      }
      final r = await _runner('df', ['-Pk', _existingAncestor(path)]);
      return r.exitCode == 0 ? parseDfAvailableBytes('${r.stdout}') : null;
    } on ProcessException catch (e) {
      _log.warning('free-space probe failed: $e');
      return null;
    }
  }

  /// `df` needs an existing path; the models dir may not exist yet.
  static String _existingAncestor(String path) {
    var dir = p.absolute(path);
    while (!Directory(dir).existsSync()) {
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return dir;
  }
}
