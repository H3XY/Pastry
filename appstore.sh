#!/bin/bash
# Builds the Mac App Store package: build/Pastry-AppStore.pkg
#
#   ./appstore.sh
#
# Needs, on this Mac:
#   - an "Apple Distribution" certificate (signs the app) and a
#     "Mac Installer Distribution" / "3rd Party Mac Developer Installer" certificate (signs the .pkg)
#   - a Mac App Store provisioning profile for com.h3xy.pastry saved as AppStore.provisionprofile
#     in this folder (it's git-ignored), or PROFILE=/path/to/profile
# Upload the .pkg with Apple's Transporter app, or `xcrun altool --upload-package`.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="com.h3xy.pastry"
PROFILE="${PROFILE:-AppStore.provisionprofile}"
APP="build/Pastry.app"
PKG="build/Pastry-AppStore.pkg"
# App Store Connect needs a higher build number on every upload; a timestamp always is.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

fail() { echo "✗ $*" >&2; exit 1; }

[[ -f "$PROFILE" ]] || fail "No provisioning profile at $PROFILE (see the top of this script)"
APP_IDENTITY="${APP_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -nE 's/.*"((Apple Distribution|3rd Party Mac Developer Application): [^"]+)".*/\1/p' | head -1)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(security find-identity -v \
  | sed -nE 's/.*"((Mac Installer Distribution|3rd Party Mac Developer Installer): [^"]+)".*/\1/p' | head -1)}"
[[ -n "$APP_IDENTITY" ]] || fail "No Apple Distribution certificate in the keychain"
[[ -n "$INSTALLER_IDENTITY" ]] || fail "No Mac Installer Distribution certificate in the keychain"

# The profile says which team and app ID this build is for; the entitlements must match it.
mkdir -p build
security cms -D -i "$PROFILE" > build/profile.plist
TEAM=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" build/profile.plist)
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" build/profile.plist)
[[ "$APP_ID" == "$TEAM.$BUNDLE_ID" ]] || fail "Profile is for $APP_ID, expected $TEAM.$BUNDLE_ID"

# 1. Universal build with the App Store switch (no GitHub update check, no move prompt).
UNIVERSAL=1 SIGN_IDENTITY=- SWIFT_FLAGS="-D APPSTORE" ./build.sh
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
# A profile downloaded with a browser carries com.apple.quarantine, and App Store Connect
# rejects packages containing it (error 91109). Strip all extended attributes before signing.
xattr -cr "$APP"

# 2. Sandboxed signature for the App Store.
cat > build/AppStore.entitlements <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.application-identifier</key>
    <string>$APP_ID</string>
    <key>com.apple.developer.team-identifier</key>
    <string>$TEAM</string>
</dict>
</plist>
EOF
codesign --force --options runtime --entitlements build/AppStore.entitlements --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# 3. Installer package, the format App Store Connect accepts for Mac apps.
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG" | head -3
echo "✓ Built $PKG (version $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist"), build $BUILD_NUMBER)"
