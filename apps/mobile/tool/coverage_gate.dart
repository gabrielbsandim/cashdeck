import 'dart:io';

final class Threshold {
  const new(this.label, this.minimum, this.matches);

  final String label;
  final double minimum;
  final bool Function(String path) matches;
}

final class Tally {
  int hit = 0;
  int found = 0;

  double get percent => found == 0 ? 100 : hit * 100 / found;
}

const excluded = ['lib/main.dart', 'lib/l10n/generated/'];

final thresholds = [
  Threshold('domain', 100, (path) => path.contains('/domain/')),
  Threshold('application', 100, (path) => path.contains('/application/')),
  Threshold('core', 95, (path) => path.startsWith('lib/core/')),
  Threshold('total', 90, (_) => true),
];

Map<String, Tally> parseLcov(String content) {
  final tallies = <String, Tally>{};
  Tally? current;
  for (final line in content.split('\n')) {
    if (line.startsWith('SF:')) {
      current = tallies.putIfAbsent(line.substring(3).trim(), Tally.new);
      continue;
    }
    if (current == null || !line.startsWith('DA:')) continue;
    final hits = int.parse(line.substring(3).split(',')[1]);
    current.found++;
    if (hits > 0) current.hit++;
  }
  return tallies;
}

void main(List<String> args) {
  final file = File(args.isEmpty ? 'coverage/lcov.info' : args.first);
  if (!file.existsSync()) {
    stderr.writeln(
      'No coverage report at ${file.path}. Run flutter test --coverage first.',
    );
    exit(2);
  }

  final files = parseLcov(file.readAsStringSync())
    ..removeWhere((path, _) => excluded.any(path.startsWith));
  var failed = false;

  for (final threshold in thresholds) {
    final tally = Tally();
    for (final entry in files.entries.where(
      (entry) => threshold.matches(entry.key),
    )) {
      tally
        ..hit += entry.value.hit
        ..found += entry.value.found;
    }
    final passed = tally.percent >= threshold.minimum;
    failed = failed || !passed;
    stdout.writeln(
      '${passed ? 'ok  ' : 'FAIL'} ${threshold.label.padRight(12)} '
      '${tally.percent.toStringAsFixed(1)}% (min ${threshold.minimum}%)',
    );
  }

  final uncovered =
      files.entries.where((entry) => entry.value.percent < 100).toList()
        ..sort((a, b) => a.value.percent.compareTo(b.value.percent));
  for (final entry in uncovered) {
    stdout.writeln(
      '     ${entry.value.percent.toStringAsFixed(1).padLeft(5)}% ${entry.key}',
    );
  }

  if (failed) exit(1);
}
