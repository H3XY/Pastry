#!/bin/bash
# Renders the App Store screenshots into AppStore/ from Pastry's real panel with demo data.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SOURCES=$(ls Sources/*.swift | grep -v '/App.swift$')
# shellcheck disable=SC2086
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  $SOURCES tools/screenshots/main.swift -o build/make-screenshots
./build/make-screenshots AppStore
