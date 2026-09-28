#!/bin/zsh
# Local development archive only. This does not notarize or publish a release.
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="${STAXRIP_BUILD_DIR:-$PROJECT_DIR/.build}"
swift build -c release --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR"
mkdir -p "$PROJECT_DIR/Distribution"
PACKAGE_DIR="$(mktemp -d "$PROJECT_DIR/Distribution/DeveloperPreview.XXXXXX")"
APP_DIR="$PACKAGE_DIR/StaxRip.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/release/StaxRipMac" "$APP_DIR/Contents/MacOS/StaxRipMac"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/THIRD-PARTY-NOTICES.md" "$APP_DIR/Contents/Resources/THIRD-PARTY-NOTICES.md"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PACKAGE_DIR/StaxRip-DeveloperPreview.zip"
echo "Local development archive: $PACKAGE_DIR/StaxRip-DeveloperPreview.zip"
echo "Ad-hoc signed only; not notarized or approved for distribution. External FFmpeg is not bundled."
