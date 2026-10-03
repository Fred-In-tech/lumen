#!/usr/bin/env bash
# One-shot quality gate: format, analyze, tests, coverage, licenses.
# Usage: bash tool/verify.sh            (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== pub get"; flutter pub get >/dev/null
echo "== format"; dart format --output=none --set-exit-if-changed packages/lumen_core server app/lib app/test app/integration_test
echo "== analyze core";   (cd packages/lumen_core && dart analyze --fatal-infos)
echo "== analyze server"; (cd server && dart analyze --fatal-infos)
echo "== analyze app";    (cd app && flutter analyze)
echo "== test core + coverage"
(cd packages/lumen_core && dart run coverage:test_with_coverage >/dev/null && dart run tool/coverage_check.dart coverage/lcov.info 80)
echo "== test server"; (cd server && dart test)
echo "== test app";    (cd app && flutter test)
echo "== licenses";    dart run tool/check_licenses.dart >/dev/null && echo "licenses OK"
echo "== secrets";     ! git grep -nE "sk-ant-[A-Za-z0-9]" -- . ':!tool/verify.sh' && echo "no secrets"
echo "ALL CHECKS PASSED"
