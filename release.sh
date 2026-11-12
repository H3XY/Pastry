#!/bin/bash
# Builds, signs with Developer ID, notarizes, and publishes a Pastry release.
#
#   ./release.sh v1.2.3
#
# Run on a Mac with:
#   - a "Developer ID Application" certificate in the keychain
#     (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application)
#   - notarization credentials saved as a keychain profile (once):
#       xcrun notarytool store-credentials pastry-notary --apple-id <you> --team-id <TEAMID>
#     Override the profile name with NOTARY_PROFILE=..., the identity with SIGN_IDENTITY=...
#   - gh signed in to GitHub
set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:?usage: ./release.sh vX.Y.Z}"
PROFILE="${NOTARY_PROFILE:-pastry-notary}"
APP="build/Pastry.app"
ZIP="build/Pastry-$TAG.zip"

fail() { echo "✗ $*" >&2; exit 1; }

# 1. Only release what's on an up-to-date, clean main, with a matching version.
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
[[ "v$VERSION" == "$TAG" ]] || fail "Tag $TAG doesn't match Info.plist version $VERSION"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "Switch to main first"
[[ -z "$(git status --porcelain)" ]] || fail "Working tree has uncommitted changes"
git fetch -q origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "Local main differs from origin/main"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "Tag $TAG already exists"
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null && fail "Tag $TAG already exists on GitHub"
# A branch with the tag's name makes "$TAG" ambiguous to git; catch it before spending time notarizing.
git rev-parse -q --verify "refs/heads/$TAG" >/dev/null && fail "A local branch is named $TAG; rename or delete it first"
git ls-remote --exit-code --heads origin "refs/heads/$TAG" >/dev/null && fail "A branch on GitHub is named $TAG; rename or delete it first"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || fail "No Developer ID Application certificate in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || fail "No notarization profile '$PROFILE' (see the top of this script)"

# 2. Universal build, then sign with Developer ID + hardened runtime (required for notarization).
UNIVERSAL=1 SIGN_IDENTITY=- ./build.sh
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# 3. Notarize, staple the ticket to the app, and check Gatekeeper accepts it.
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# 4. Re-zip the stapled app and publish.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "Pastry-$TAG.zip" > "Pastry-$TAG.zip.sha256")

cat > build/notes.md <<EOF
## Install

1. Download **Pastry-$TAG.zip** below and unzip it.
2. Drag **Pastry.app** into your Applications folder and open it.
3. Allow **Accessibility** when asked (System Settings → Privacy & Security → Accessibility),
   so Pastry can paste for you.

Then press **⇧⌘V** anywhere. Look for the pasty in your menu bar. 🥟

Signed with Developer ID and notarized by Apple. Works on macOS 13 or later, on Apple Silicon and Intel Macs.
EOF

git tag -a "$TAG" -m "Pastry $TAG"
git push origin "refs/tags/$TAG"   # full ref name, so it can never be mistaken for a branch
gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
  --verify-tag --title "Pastry $TAG" --notes-file build/notes.md --generate-notes
echo "✓ Published Pastry $TAG"
