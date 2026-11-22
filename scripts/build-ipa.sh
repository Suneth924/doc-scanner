#!/usr/bin/env bash
# Builds an unsigned DocScanner.ipa for sideloading with AltStore.
# AltStore re-signs the app with your Apple ID when it installs it,
# so no signing team or provisioning profile is needed here.
#
# Usage: scripts/build-ipa.sh
# Output: build/DocScanner.ipa (override the folder with OUTPUT_DIR=...)

set -euo pipefail

APP_NAME="DocScanner"
CONFIGURATION="${CONFIGURATION:-Release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
SYMROOT="$ROOT/build/xcode"
STAGING="$ROOT/build/ipa-staging"
IPA="$OUTPUT_DIR/$APP_NAME.ipa"

for tool in xcodegen xcodebuild zip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' not found." >&2
    [ "$tool" = xcodegen ] && echo "Install it with: brew install xcodegen" >&2
    [ "$tool" = xcodebuild ] && echo "Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
  fi
done

echo "==> Generating Xcode project"
xcodegen generate --quiet

echo "==> Building $APP_NAME ($CONFIGURATION, generic iOS device, unsigned)"
rm -rf "$SYMROOT"
LOG="$ROOT/build/xcodebuild.log"
if ! xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -target "$APP_NAME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    SYMROOT="$SYMROOT" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build >"$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | tail -n 30 >&2 || true
  echo "error: build failed. Full log: $LOG" >&2
  exit 1
fi

APP_PATH="$SYMROOT/$CONFIGURATION-iphoneos/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: build finished but $APP_PATH is missing. Full log: $LOG" >&2
  exit 1
fi

echo "==> Packaging $APP_NAME.ipa"
rm -rf "$STAGING" "$IPA"
mkdir -p "$STAGING/Payload"
cp -R "$APP_PATH" "$STAGING/Payload/"
(cd "$STAGING" && zip -qry "$IPA" Payload)
rm -rf "$STAGING"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist" 2>/dev/null || echo '?')"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist" 2>/dev/null || echo '?')"
SIZE="$(du -h "$IPA" | cut -f1 | tr -d ' ')"

echo
echo "Done: $APP_NAME $VERSION ($BUILD), $SIZE"
echo "IPA:  $IPA"
echo
echo "Install it with AltStore on your iPhone: My Apps, then +, then pick this file."
