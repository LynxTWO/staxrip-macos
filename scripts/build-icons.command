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
xcrun iconutil --convert icns --output "$OUTPUT_DIR/StaxRip.icns" "$ICONSET"
if (( $# >= 2 )); then
    RESOURCE_DIR="$2"
    mkdir -p "$RESOURCE_DIR"
    cp "$OUTPUT_DIR/StaxRip.icns" "$RESOURCE_DIR/StaxRip.icns"
    cp "$OUTPUT_DIR/artwork/default-128.png" "$RESOURCE_DIR/StaxRipBrandLight.png"
    cp "$OUTPUT_DIR/artwork/dark-128.png" "$RESOURCE_DIR/StaxRipBrandDark.png"
fi
