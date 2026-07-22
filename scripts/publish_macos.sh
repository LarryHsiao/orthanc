#!/usr/bin/env bash
#
# Orthanc — build a signed, notarized macOS DMG, optionally publish it to
# GitHub Releases.
#
# Runs interactively on this machine: signs with the Developer ID Application
# identity already in the local login keychain (no temp keychain, no CI
# secrets) and fetches the Apple ID + app-specific password from Vaultwarden
# via secret.sh. Adapted from Heimdall's scripts/build_macos_dmg.sh, trimmed
# for a local run — no cert import/teardown, no provisioning profile (Orthanc
# has none and needs none: sandbox is off, entitlements are empty).
#
# Usage:
#   scripts/publish_macos.sh              # build, sign, notarize, staple
#   scripts/publish_macos.sh --publish    # also create/upload a GitHub release
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - A "Developer ID Application" identity in the login keychain
#   - Vaultwarden reachable via ~/.claude/hooks/secret.sh, item
#     "apple-notarization" (login.username = Apple ID, login.password =
#     app-specific password)
#   - create-dmg (optional; falls back to hdiutil if absent)
#   - gh CLI, authenticated (only needed for --publish)
#
# Output:
#   build/publish/orthanc.dmg   signed, notarized, stapled
#
set -euo pipefail

APP_NAME="orthanc"
OUTPUT_DIR="build/publish"
APPLE_TEAM_ID="2SX9WGZ5F8"
PUBLISH=0

for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    *)
      echo "error: unknown argument '$arg'" >&2
      exit 1
      ;;
  esac
done

VERSION=$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$VERSION" ]; then
  echo "error: could not read version from pubspec.yaml" >&2
  exit 1
fi
echo "==> Version: $VERSION"

echo "==> Resolving Apple credentials from Vaultwarden"
APPLE_ID="$(~/.claude/hooks/secret.sh apple-notarization username)"
APPLE_APP_PASSWORD="$(~/.claude/hooks/secret.sh apple-notarization password)"
if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
  echo "error: could not resolve Apple ID / app-specific password from Vaultwarden (item: apple-notarization)" >&2
  exit 1
fi

IDENTITY_LINE=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" \
  | head -1)
IDENTITY_HASH=$(echo "$IDENTITY_LINE" | awk '{print $2}')
IDENTITY_NAME=$(echo "$IDENTITY_LINE" | awk -F'"' '{print $2}')
if [ -z "$IDENTITY_HASH" ]; then
  echo "error: no Developer ID Application identity found in the login keychain" >&2
  exit 1
fi
echo "==> Signing identity: $IDENTITY_NAME ($IDENTITY_HASH)"

echo "==> Resolving Flutter dependencies"
flutter pub get

echo "==> Building macOS release"
flutter build macos --release

APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

ENTITLEMENTS_SRC="macos/Runner/Release.entitlements"
if [ ! -f "$ENTITLEMENTS_SRC" ]; then
  echo "error: entitlements not found at $ENTITLEMENTS_SRC" >&2
  exit 1
fi

echo "==> Code-signing $APP_PATH"
codesign --force --deep --verify --verbose \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_SRC" \
  --sign "$IDENTITY_HASH" \
  "$APP_PATH"

echo "==> Verifying app signature"
codesign --verify --strict --verbose=2 "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
DMG_PATH="$OUTPUT_DIR/$APP_NAME.dmg"
rm -f "$DMG_PATH"

DMG_STAGE="$OUTPUT_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"

if command -v create-dmg >/dev/null 2>&1; then
  echo "==> Building DMG with create-dmg"
  # create-dmg makes its own Applications symlink via --app-drop-link; a
  # pre-staged one collides with it ("File exists") and create-dmg aborts,
  # silently falling through to the plainer hdiutil path below.
  create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 185 \
    "$DMG_PATH" \
    "$DMG_STAGE/" || true
fi

if [ ! -f "$DMG_PATH" ]; then
  echo "==> create-dmg unavailable or failed; falling back to hdiutil"
  # hdiutil has no equivalent of --app-drop-link, so the symlink must be
  # staged by hand for this path only.
  ln -sfn /Applications "$DMG_STAGE/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
fi

rm -rf "$DMG_STAGE"

echo "==> Code-signing $DMG_PATH"
codesign --force --timestamp \
  --sign "$IDENTITY_HASH" \
  "$DMG_PATH"

echo "==> Submitting to Apple notary service (this can take several minutes)"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

echo "==> Stapling the notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying staple"
xcrun stapler validate "$DMG_PATH"

echo "==> Done. Signed and notarized DMG at: $DMG_PATH"

if [ "$PUBLISH" -eq 1 ]; then
  TAG="v$VERSION"
  echo "==> Publishing to GitHub Releases as $TAG"
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "$TAG" --generate-notes
  fi
  gh release upload "$TAG" "$DMG_PATH" --clobber
  echo "==> Published: $(gh release view "$TAG" --json url -q .url)"
else
  echo "==> Skipping publish (pass --publish to create/update the GitHub release)"
fi
