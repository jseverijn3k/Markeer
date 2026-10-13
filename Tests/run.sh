#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${MARKEER_BUILD_DIR:-.build}"
export MARKEER_BUILD_DIR="$BUILD"
./build.sh
mkdir -p "$BUILD/js-tests"
cp Tests/package.json "$BUILD/js-tests/package.json"
npm install --cache "$BUILD/npm-cache" --prefix "$BUILD/js-tests" --no-audit --no-fund
"$BUILD/MarkeerTests" --render Tests/fixture.md > "$BUILD/fixture.json"
NODE_PATH="$(cd "$BUILD/js-tests/node_modules" && pwd)" node Tests/editor-tests.cjs Tests/fixture.md "$BUILD/fixture.json"
