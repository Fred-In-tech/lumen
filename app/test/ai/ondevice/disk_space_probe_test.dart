import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/disk_space_probe.dart';
import 'package:lumen/ai/ondevice/disk_space_probe_io.dart';
import 'package:lumen/platform/platform_info.dart';

const _mac = PlatformInfo(
  isMacOS: true,
  isWindows: false,
  isLinux: false,
  isIOS: false,
  isAndroid: false,
);
const _windows = PlatformInfo(
  isMacOS: false,
  isWindows: true,
  isLinux: false,
  isIOS: false,
  isAndroid: false,
);
const _ios = PlatformInfo(
  isMacOS: false,
  isWindows: false,
  isLinux: false,
  isIOS: true,
  isAndroid: false,
);

void main() {
  test('parses macOS and Linux `df -Pk` output', () {
    const mac =
        'Filesystem     1024-blocks      Used Available Capacity  Mounted on\n'
        '/dev/disk3s3s1   971350180  12583260   3355443    79%    /\n';
    expect(parseDfAvailableBytes(mac), 3355443 * 1024);
    const linux =
        'Filesystem     1024-blocks    Used Available Capacity Mounted on\n'
        '/dev/sda1        41152736 9876543  29163600      26% /home/my disk\n';
    expect(parseDfAvailableBytes(linux), 29163600 * 1024);
    expect(parseDfAvailableBytes('garbage'), isNull);
    expect(parseDfAvailableBytes(''), isNull);
  });

  test('parses PowerShell Get-PSDrive output and drive letters', () {
    expect(parsePowerShellFreeBytes('123456789\r\n'), 123456789);
    expect(parsePowerShellFreeBytes(''), isNull);
    expect(windowsDriveLetter(r'c:\Users\me\AppData'), 'C');
    expect(windowsDriveLetter('/Users/me'), isNull);
  });

  test(
    'runs df on desktop Unix, PowerShell on Windows, nothing on mobile',
    () async {
      final calls = <String>[];
      Future<ProcessResult> fake(String exe, List<String> args) async {
        calls.add('$exe ${args.join(' ')}');
        return ProcessResult(
          0,
          0,
          exe == 'df'
              ? 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
                    '/dev/x 100 50 42 50% /\n'
              : '4096\n',
          '',
        );
      }

      expect(
        await ProcessDiskSpaceProbe(_mac, run: fake).freeBytes('/'),
        42 * 1024,
      );
      expect(
        await ProcessDiskSpaceProbe(_windows, run: fake).freeBytes(r'D:\x'),
        4096,
      );
      expect(
        await ProcessDiskSpaceProbe(_ios, run: fake).freeBytes('/'),
        isNull,
      );
      expect(calls.first, startsWith('df -Pk '));
      expect(calls.last, contains('Get-PSDrive -Name D'));
      expect(calls, hasLength(2));
    },
  );

  test('real df on this host walks up to an existing directory', () async {
    final free = await ProcessDiskSpaceProbe(_mac)
        .freeBytes('${Directory.systemTemp.path}/does/not/exist/yet');
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  }, skip: Platform.isMacOS || Platform.isLinux ? false : 'needs df');
}
