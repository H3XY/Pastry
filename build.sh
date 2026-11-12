#!/bin/bash
# Builds Pastry.app. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Pastry.app"
# UNIVERSAL=1 builds for both Apple Silicon and Intel (used for releases);
# otherwise only this Mac's architecture, which is faster.
if [[ "${UNIVERSAL:-}" == "1" ]]; then ARCHS=(arm64 x86_64); else ARCHS=("$(uname -m)"); fi

rm -rf "$APP" build/slices
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/slices

for ARCH in "${ARCHS[@]}"; do
  xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos13.0" \
    Sources/*.swift \
    -o "build/slices/Pastry-$ARCH"
done
lipo -create build/slices/Pastry-* -output "$APP/Contents/MacOS/Pastry"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a real certificate when one is available, so macOS keeps the
# Accessibility permission across rebuilds. An ad-hoc signature (the fallback,
# also used on CI) changes on every build and macOS then forgets the permission.
# Override with SIGN_IDENTITY="Your Identity" ./build.sh, or SIGN_IDENTITY=- for ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -nE 's/.*"((Apple Development|Developer ID Application): [^"]+)".*/\1/p' | head -1)}"
codesign --force --sign "${IDENTITY:--}" "$APP"
[[ -z "$IDENTITY" || "$IDENTITY" == "-" ]] && IDENTITY="ad-hoc"
echo "Built $APP (signed: $IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/Pastry.app"
  pkill -x Pastry 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
