// License allow-list check for every resolved Dart/Flutter package.
//
// Usage (repo root, after `flutter pub get`): dart run tool/check_licenses.dart
// Prints one line per package and exits 1 if any license is copyleft,
// non-commercial or unknown. Pass --markdown to emit a table for docs/LICENSES.md.
import 'dart:convert';
import 'dart:io';

const _ownPackages = {'lumen', 'lumen_core', 'lumen_server', 'lumen_workspace'};

String _classify(String text) {
  final t = text.toLowerCase();
  // MPL-2.0 text names the GPL family in its "secondary license" clause: test it first.
  // File-level copyleft; commercial use is fine when the files are used unmodified.
  if (t.contains('mozilla public license')) return 'MPL-2.0 (unmodified use OK)';
  if (t.contains('gnu affero') || t.contains('agpl')) return 'AGPL (BANNED)';
  if (t.contains('gnu lesser') || t.contains('lgpl')) return 'LGPL (BANNED)';
  if (t.contains('gnu general public')) return 'GPL (BANNED)';
  if (t.contains('non-commercial') || t.contains('noncommercial')) return 'Non-commercial (BANNED)';
  if (t.contains('apache license')) return 'Apache-2.0';
  if (t.contains('permission is hereby granted, free of charge')) return 'MIT';
  if (t.contains('permission to use, copy, modify, and/or distribute')) return 'ISC';
  if (t.contains('redistribution and use in source and binary forms')) {
    return t.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (t.contains('zlib') && t.contains('altered source versions')) return 'zlib';
  return 'UNKNOWN';
}

void main(List<String> args) {
  final markdown = args.contains('--markdown');
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    stderr.writeln('Run `flutter pub get` at the repo root first.');
    exitCode = 2;
    return;
  }
  final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  final packages = (json['packages']! as List).cast<Map<String, Object?>>();
  var bad = 0;
  final rows = <String>[];
  for (final p in packages..sort((a, b) => (a['name']! as String).compareTo(b['name']! as String))) {
    final name = p['name']! as String;
    if (_ownPackages.contains(name)) continue;
    final rootUri = Uri.parse(p['rootUri']! as String);
    final root = rootUri.isAbsolute ? rootUri : config.parent.uri.resolveUri(rootUri);
    final dir = Directory.fromUri(root);
    final license = ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING']
        .map((f) => File('${dir.path}/$f'))
        .where((f) => f.existsSync())
        .firstOrNull;
    var kind = license == null ? 'UNKNOWN (no LICENSE file)' : _classify(license.readAsStringSync());
    // The Flutter SDK's own packages (sky_engine, flutter, flutter_test…) are BSD-3.
    if (kind.startsWith('UNKNOWN') && dir.path.contains('/flutter/') && (dir.path.contains('/packages/') || dir.path.contains('/bin/cache/pkg/'))) {
      kind = 'BSD-3-Clause (Flutter SDK)';
    }
    final banned = kind.contains('BANNED') || kind.startsWith('UNKNOWN');
    if (banned) bad++;
    rows.add(markdown ? '| $name | $kind |' : '${banned ? '✗' : '✓'} $name: $kind');
  }
  if (markdown) stdout.writeln('| Package | License |\n|---|---|');
  rows.forEach(stdout.writeln);
  stdout.writeln(markdown ? '' : '\n${rows.length} packages checked, $bad problems.');
  if (bad > 0) exitCode = 1;
}
