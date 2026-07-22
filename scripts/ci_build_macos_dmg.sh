#!/usr/bin/env bash
#
# Orthanc — build a signed, notarized macOS DMG on an unattended CI runner.
#
# Ported from Heimdall's scripts/build_macos_dmg.sh. Designed to run
# end-to-end with no interactive agent: secrets arrive through environment
# variables, the script creates a temporary keychain scoped to this build,
# imports the Developer ID certificate into it, signs the .app and DMG,
# submits to Apple's notary service via `notarytool --wait`, staples the
# ticket, and tears the keychain down on exit (success or failure).
#
# Unlike scripts/publish_macos.sh (this repo's interactive local script,
# which signs with whatever Developer ID identity is already in the login
# keychain and reads Apple credentials from Vaultwarden), a CI runner has no
# such keychain or Vaultwarden session — every credential must arrive as an
# env var, and the signing identity must be imported fresh each run.
#
# Orthanc needs no provisioning profile: macos/Runner/*.entitlements are
# empty (App Sandbox is off, by design — see the project README), so there
# is nothing a profile would need to grant. Heimdall's equivalent script
# embeds one; this one deliberately does not.
#
# Prerequisites on the runner:
#   - macOS with Xcode (notarytool, stapler, codesign)
#   - Flutter SDK on PATH (or FLUTTER_BIN override)
#
# Required environment variables:
#   DEVELOPER_ID_CERT_BASE64    base64 of Developer ID Application .p12
#   DEVELOPER_ID_CERT_PASSWORD  password for the .p12
#   NOTARY_API_KEY_BASE64       base64 of App Store Connect API key .p8
#   NOTARY_API_KEY_ID           App Store Connect API key id
#   NOTARY_API_ISSUER_ID        App Store Connect API issuer id
#   KEYCHAIN_PASSWORD           password for the temporary keychain
#                               (any value — scoped to this build)
#
# Optional environment variables:
#   FLUTTER_BIN                 flutter binary (default: "flutter")
#   APP_NAME                    bundle name (default: "orthanc")
#   OUTPUT_DIR                  where to drop the DMG (default: "build/publish")
#
# Output:
#   $OUTPUT_DIR/$APP_NAME.dmg   signed, notarized, stapled
#
# Usage:
#   scripts/ci_build_macos_dmg.sh
#
set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
APP_NAME="${APP_NAME:-orthanc}"
OUTPUT_DIR="${OUTPUT_DIR:-build/publish}"

require() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "error: required environment variable $name is not set" >&2
    exit 1
  fi
}

require DEVELOPER_ID_CERT_BASE64
require DEVELOPER_ID_CERT_PASSWORD
require NOTARY_API_KEY_BASE64
require NOTARY_API_KEY_ID
require NOTARY_API_ISSUER_ID
require KEYCHAIN_PASSWORD

WORK_DIR="$(mktemp -d)"
KEYCHAIN_PATH="$WORK_DIR/build.keychain-db"
CERT_PATH="$WORK_DIR/cert.p12"
KEY_PATH="$WORK_DIR/notary.p8"

cleanup() {
  if [ -f "$KEYCHAIN_PATH" ]; then
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "==> Decoding secrets"
printf '%s' "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > "$CERT_PATH"
printf '%s' "$NOTARY_API_KEY_BASE64" | base64 --decode > "$KEY_PATH"

echo "==> Creating temporary keychain"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$DEVELOPER_ID_CERT_PASSWORD" \
  -T /usr/bin/codesign
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

# Prepend the build keychain to the user search list so codesign can find it.
USER_KEYCHAINS=$(security list-keychains -d user | tr -d '"' | xargs)
security list-keychains -d user -s "$KEYCHAIN_PATH" $USER_KEYCHAINS

IDENTITY_LINE=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | grep "Developer ID Application" \
  | head -1)
IDENTITY_HASH=$(echo "$IDENTITY_LINE" | awk '{print $2}')
IDENTITY_NAME=$(echo "$IDENTITY_LINE" | awk -F'"' '{print $2}')
if [ -z "$IDENTITY_HASH" ]; then
  echo "error: no Developer ID Application identity found in the build keychain" >&2
  exit 1
fi
echo "==> Signing identity: $IDENTITY_NAME ($IDENTITY_HASH)"

echo "==> Resolving Flutter dependencies"
$FLUTTER_BIN pub get

echo "==> Building macOS release"
$FLUTTER_BIN build macos --release

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
  --keychain "$KEYCHAIN_PATH" \
  --sign "$IDENTITY_HASH" \
  "$APP_PATH"

echo "==> Verifying app signature"
codesign --verify --strict --verbose=2 "$APP_PATH"

echo "==> Building DMG"
mkdir -p "$OUTPUT_DIR"
DMG_PATH="$OUTPUT_DIR/$APP_NAME.dmg"
rm -f "$DMG_PATH"

DMG_STAGE="$WORK_DIR/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Code-signing $DMG_PATH"
codesign --force --timestamp \
  --keychain "$KEYCHAIN_PATH" \
  --sign "$IDENTITY_HASH" \
  "$DMG_PATH"

echo "==> Submitting to Apple notary service (this can take several minutes)"
NOTARY_ARGS=( --key "$KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --wait )
# notarytool's --issuer expects a UUID (Team API keys). Individual API
# keys take only --key and --key-id; passing a non-UUID Team Id there is
# rejected with "must be a valid UUID". Detect and omit accordingly.
if [[ -n "${NOTARY_API_ISSUER_ID:-}" && \
      "$NOTARY_API_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  NOTARY_ARGS+=( --issuer "$NOTARY_API_ISSUER_ID" )
fi
xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}"

echo "==> Stapling the notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying staple"
xcrun stapler validate "$DMG_PATH"

echo "==> Done. Signed and notarized DMG at: $DMG_PATH"
