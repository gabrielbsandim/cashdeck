#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo "== format"
dart format --output=none --set-exit-if-changed lib test tool

echo "== analyze"
flutter analyze

echo "== test + coverage"
flutter test --coverage

echo "== coverage gate"
dart run tool/coverage_gate.dart coverage/lcov.info
