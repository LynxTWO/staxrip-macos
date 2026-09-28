#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="${STAXRIP_BUILD_DIR:-$PROJECT_DIR/.build}"
APP_DIR="$PROJECT_DIR/Preview/StaxRip.app"
swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/debug/StaxRipMac" "$APP_DIR/Contents/MacOS/StaxRipMac"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/THIRD-PARTY-NOTICES.md" "$APP_DIR/Contents/Resources/THIRD-PARTY-NOTICES.md"
codesign --force --sign - "$APP_DIR"
echo "Built: $APP_DIR"
echo "Quit the running prototype, then open Preview/StaxRip.app to see the changes."
