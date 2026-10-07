import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/app_info.dart';

void main() {
  test('kAppVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(kAppVersion, m!.group(1));
  });
}
