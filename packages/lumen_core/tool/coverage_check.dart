// Fails (exit 1) when line coverage in an lcov file is below a threshold.
// Usage: dart run tool/coverage_check.dart coverage/lcov.info 80
import 'dart:io';

void main(List<String> args) {
  final file = File(args.isNotEmpty ? args[0] : 'coverage/lcov.info');
  final threshold = double.parse(args.length > 1 ? args[1] : '80');
  var found = 0, hit = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) found += int.parse(line.substring(3));
    if (line.startsWith('LH:')) hit += int.parse(line.substring(3));
  }
  final pct = found == 0 ? 0.0 : hit * 100 / found;
  stdout.writeln('Line coverage: ${pct.toStringAsFixed(1)}% ($hit/$found), threshold $threshold%');
  if (pct < threshold) exitCode = 1;
}
