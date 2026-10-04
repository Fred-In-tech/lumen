#!/usr/bin/env bash
# One-shot quality gate: format, analyze, tests, coverage, licenses.
# Usage: bash tool/verify.sh            (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== pub get"; flutter pub get >/dev/null
# LiteRT host libraries for model tests: the package's own lookup misses pub
# workspaces, so point it at the bundled macOS dylibs explicitly.
if [[ "$(uname)" == "Darwin" ]]; then
  litert_root=$(python3 -c 'import json; c = json.load(open(".dart_tool/package_config.json")); print(next(p["rootUri"] for p in c["packages"] if p["name"] == "flutter_litert").removeprefix("file://"))' 2>/dev/null || true)
  litert_res="$litert_root/macos/flutter_litert/Sources/flutter_litert/Resources"
  if [[ -d "$litert_res" ]]; then
    export TFLITE_LIB_PATH="$litert_res/libtensorflowlite_c-mac.dylib"
    export LITERT_LIB_PATH="$litert_res/libLiteRt.dylib"
  fi
fi
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
