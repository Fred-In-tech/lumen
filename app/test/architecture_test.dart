import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the cross-platform rules from docs/PLAN.md §1.3 and docs/DESIGN.md §1.3.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String rel(File f) => f.path.replaceAll(r'\', '/');

  test('dart:io and dart:isolate are only imported by *_io.dart files (web + Windows safety)', () {
    final offenders = [
      for (final f in libFiles)
        if (!rel(f).endsWith('_io.dart') &&
            RegExp(
              r"^import 'dart:(io|isolate)'",
              multiLine: true,
            ).hasMatch(f.readAsStringSync()))
          rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('*_io.dart files are only imported from conditional exports or other io files', () {
    final offenders = <String>[];
    for (final f in libFiles) {
      if (rel(f).endsWith('_io.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(
        r"^import '([^']+_io\.dart)'",
        multiLine: true,
      ).allMatches(src)) {
        offenders.add('${rel(f)} -> ${m.group(1)}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('Platform.isX is only read in platform_info_io.dart', () {
    final offenders = [
      for (final f in libFiles)
        if (!rel(f).endsWith('platform_info_io.dart') &&
            f.readAsStringSync().contains('Platform.is'))
          rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('no Material/Cupertino icon sets (Lucide only)', () {
    final offenders = [
      for (final f in libFiles)
        if (RegExp(r'(?<![A-Za-z])(Icons|CupertinoIcons)\.')
            .hasMatch(f.readAsStringSync()))
          rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('the brand name appears only via kBrand (lumen_core brand.dart)', () {
    final offenders = [
      for (final f in libFiles)
        if (RegExp(r'''['"]Lumen\b''').hasMatch(f.readAsStringSync())) rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('no API keys or secrets in source', () {
    final roots = [
      'lib',
      '../packages/lumen_core/lib',
      '../server/lib',
      '../server/bin',
    ];
    final offenders = <String>[];
    for (final r in roots) {
      for (final f in Directory(
        r,
      ).listSync(recursive: true).whereType<File>()) {
        if (RegExp(r'sk-ant-[A-Za-z0-9]').hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('every plugin in pubspec is known to support Windows or is guarded', () {
    const windowsOk = {
      'flutter_riverpod',
      'file_picker',
      'desktop_drop',
      'path_provider',
      'path',
      'exif',
      'share_plus',
      'crypto',
      'uuid',
      'lucide_icons_flutter',
      'collection',
      'logging',
      'image',
      'http',
      // Bundles libtensorflowlite_c-win.dll + libLiteRt.dll (ffiPlugin).
      'flutter_litert',
      'cross_file',
      'lumen_core',
      'flutter',
    };
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final deps = RegExp(
      r'^dependencies:\n((?:  .*\n|\n)*)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    final names = RegExp(
      r'^  ([a-z_]+):',
      multiLine: true,
    ).allMatches(deps).map((m) => m.group(1)!).toSet();
    expect(
      names.difference(windowsOk),
      isEmpty,
      reason: 'Review Windows support for new plugins',
    );
  });

  test('shaders stay under the Metal uniform-declaration limit', () {
    // On Impeller/Metal a fragment shader with more than ~32 separate
    // uniform declarations (samplers included) silently renders white,
    // while the headless tester is fine. Group vec4 uniforms into arrays
    // (with #define aliases) and keep a safety margin.
    final decl = RegExp(
      r'^\s*uniform\s+(float|vec2|vec3|vec4|sampler2D)\s+\w+',
      multiLine: true,
    );
    final over = <String>[];
    for (final f in Directory('shaders').listSync().whereType<File>()) {
      if (!f.path.endsWith('.frag')) continue;
      final n = decl.allMatches(f.readAsStringSync()).length;
      if (n > 24) over.add('${f.path}: $n');
    }
    expect(over, isEmpty);
  });
}
