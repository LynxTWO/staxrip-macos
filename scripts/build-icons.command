#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:?Pass the generated icon output directory}"
mkdir -p "$OUTPUT_DIR"
swift "$PROJECT_DIR/scripts/IconArtwork.swift" "$OUTPUT_DIR/artwork"
ICONSET="$OUTPUT_DIR/StaxRip.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    cp "$OUTPUT_DIR/artwork/default-$size.png" "$ICONSET/icon_${size}x${size}.png"
    doubled=$((size * 2))
    cp "$OUTPUT_DIR/artwork/default-$doubled.png" "$ICONSET/icon_${size}x${size}@2x.png"
done
ICON_SOURCE="$PROJECT_DIR/Resources/IconArtwork/StaxRip.icon"
# Committed SVGs keep the project editable; catch drift from the geometry source.
for layer in "$ICON_SOURCE/Assets/"*.svg; do
    cmp "$layer" "$OUTPUT_DIR/artwork/default/${layer:t}"
done
xcrun iconutil --convert icns --output "$OUTPUT_DIR/StaxRip.icns" "$ICONSET"
if (( $# >= 2 )); then
    RESOURCE_DIR="$2"
    INFO_PLIST="${3:?Pass the app Info.plist when installing icon resources}"
    mkdir -p "$RESOURCE_DIR"
    cp "$OUTPUT_DIR/StaxRip.icns" "$RESOURCE_DIR/StaxRip.icns"
    cp "$OUTPUT_DIR/artwork/default-128.png" "$RESOURCE_DIR/StaxRipBrandLight.png"
    cp "$OUTPUT_DIR/artwork/dark-128.png" "$RESOURCE_DIR/StaxRipBrandDark.png"
    # The preview bundle is reused. Never retain a modern catalog in a legacy build.
    rm -f "$RESOURCE_DIR/Assets.car"
    if /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$INFO_PLIST" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "$INFO_PLIST"
    fi
    SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
    SDK_MAJOR="${SDK_VERSION%%.*}"
    if [[ "$SDK_MAJOR" != <-> ]]; then
        print -u2 "Cannot determine macOS SDK version: $SDK_VERSION"; exit 1
    fi
    if (( SDK_MAJOR >= 26 )); then
        COMPILED_DIR="$(mktemp -d "$OUTPUT_DIR/compiled.XXXXXX")"
        xcrun actool "$ICON_SOURCE" --compile "$COMPILED_DIR" --platform macosx \
            --minimum-deployment-target 14.0 --app-icon StaxRip \
            --output-partial-info-plist "$COMPILED_DIR/icon.plist"
        test -s "$COMPILED_DIR/Assets.car"
        cp "$COMPILED_DIR/Assets.car" "$RESOURCE_DIR/Assets.car"
        /usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string StaxRip' "$INFO_PLIST"
        print "Installed native layered icon and multi-resolution fallback."
    else
        print "SDK $SDK_VERSION: installed multi-resolution icon fallback."
    fi
fi
