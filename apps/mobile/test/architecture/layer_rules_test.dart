import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

const _frameworkImports = [
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:dio/',
];

final class _Rule {
  const new(this.description, this.appliesTo, this.forbidden);

  final String description;
  final bool Function(String path) appliesTo;
  final bool Function(String import) forbidden;
}

bool _inLayer(String path, String layer) =>
    path.contains('/features/') && path.contains('/$layer/');

bool _importsLayer(String import, String layer) =>
    import.startsWith('package:cashdeck/features/') &&
    import.contains('/$layer/');

bool _importsFramework(String import) =>
    _frameworkImports.any(import.startsWith);

final _rules = [
  _Rule(
    'domain imports no framework and no other layer',
    (path) => _inLayer(path, 'domain'),
    (import) =>
        _importsFramework(import) ||
        _importsLayer(import, 'data') ||
        _importsLayer(import, 'application') ||
        _importsLayer(import, 'presentation'),
  ),
  _Rule(
    'application imports no framework, data or presentation',
    (path) => _inLayer(path, 'application'),
    (import) =>
        _importsFramework(import) ||
        _importsLayer(import, 'data') ||
        _importsLayer(import, 'presentation'),
  ),
  _Rule(
    'presentation imports no data layer and no Dio',
    (path) => _inLayer(path, 'presentation'),
    (import) =>
        _importsLayer(import, 'data') || import.startsWith('package:dio/'),
  ),
  _Rule(
    'core imports no feature',
    (path) => path.startsWith('lib/core/'),
    (import) => import.startsWith('package:cashdeck/features/'),
  ),
  _Rule(
    'no relative imports',
    (path) => true,
    (import) => !import.contains(':'),
  ),
];

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.contains('/generated/'))
      .toList();

  test('scans the source tree', () {
    expect(files, isNotEmpty);
  });

  for (final rule in _rules) {
    test(rule.description, () {
      final violations = [
        for (final file in files.where((file) => rule.appliesTo(file.path)))
          for (final match in _importPattern.allMatches(
            file.readAsStringSync(),
          ))
            if (rule.forbidden(match.group(1)!))
              '${file.path}: ${match.group(1)}',
      ];
      expect(violations, isEmpty);
    });
  }
}
