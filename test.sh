#!/bin/bash
# Compiles Pastry's sources (minus the app entry point) with Tests/main.swift and runs the tests.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
SOURCES=$(ls Sources/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  $SOURCES Tests/main.swift -o build/PastryTests
./build/PastryTests
