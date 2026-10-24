#!/bin/bash
set -euo pipefail

# Reframe the approved v2 artwork, then prepare platform-specific icon resources.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/design/app-icon-source-v2.png}"
ICONS="$ROOT/体脂秤/Assets.xcassets/AppIcon.appiconset"
PROFILES=/System/Library/ColorSync/Profiles
[[ -f "$SOURCE" ]] || { echo "Icon source not found: $SOURCE" >&2; exit 1; }
WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth:/ {print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight:/ {print $2}')
ALPHA=$(sips -g hasAlpha "$SOURCE" | awk '/hasAlpha:/ {print $2}')
[[ "$WIDTH" == "$HEIGHT" && "$ALPHA" == no ]] || {
    echo "Use a square, opaque source image; do not bake in the outer rounded mask." >&2
    exit 1
}
mkdir -p "$ROOT/docs/images"
WORK=$(mktemp -d /tmp/weightrace-icons.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
# Center crop removes 3% per edge; the v2 composition keeps its display and wave
# within these bounds. Record this rather than repeatedly cropping the output.
CROP=$((WIDTH * 94 / 100))
CROP=$((CROP / 2 * 2))
sips --cropToHeightWidth "$CROP" "$CROP" "$SOURCE" --out "$WORK/cropped.png" >/dev/null
sips --matchTo "$PROFILES/sRGB Profile.icc" --resampleHeightWidth 1024 1024 \
    -s format png "$WORK/cropped.png" --out "$ICONS/AppIcon.png" >/dev/null
sips --matchTo "$PROFILES/Generic Gray Gamma 2.2 Profile.icc" \
    -s format png "$ICONS/AppIcon.png" --out "$ICONS/AppIcon-Tinted.png" >/dev/null
# Legacy .icns is not masked like an iOS app icon. Give it its own transparent
# canvas and a continuous rounded silhouette, not an opaque square background.
xcrun swiftc -parse-as-library -module-cache-path "$WORK/ModuleCache" \
    "$ROOT/scripts/render-mac-icon.swift" -o "$WORK/render-mac-icon"
"$WORK/render-mac-icon" "$ICONS/AppIcon.png" "$WORK/MacIcon.png"
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((size * scale))
        sips --resampleHeightWidth "$pixels" "$pixels" "$WORK/MacIcon.png" \
            --out "$ICONS/AppIcon-mac-${size}@${scale}x.png" >/dev/null
    done
done
mkdir "$WORK/WeighTrace.iconset"
for size in 16 32 128 256 512; do
    cp "$ICONS/AppIcon-mac-${size}@1x.png" "$WORK/WeighTrace.iconset/icon_${size}x${size}.png"
    cp "$ICONS/AppIcon-mac-${size}@2x.png" "$WORK/WeighTrace.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$WORK/WeighTrace.iconset" -o "$ROOT/design/WeighTrace.icns"
sips --resampleHeightWidth 256 256 "$WORK/MacIcon.png" \
    --out "$ROOT/docs/images/weightrace-icon.png" >/dev/null
echo "Prepared iOS default/dark, tinted, all Mac sizes, a complete .icns, and README preview."
