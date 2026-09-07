#!/bin/bash
set -euo pipefail

# Local distributable test build. No credentials or health data are included.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/dist}"
BUILD_ROOT="$(mktemp -d /tmp/afu-mac-package.XXXXXX)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
xcodebuild -quiet -project "$PROJECT_ROOT/体脂秤.xcodeproj" -scheme 体脂秤 \
    -configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$BUILD_ROOT/build" CODE_SIGNING_ALLOWED=NO build
APP="$BUILD_ROOT/build/Build/Products/Release-maccatalyst/体脂秤.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
NAME="AFU-Scale-Mac-$VERSION-$BUILD-test"
if [[ -e "$OUTPUT_DIR/$NAME.dmg" ]]; then
    echo "Output already exists: $OUTPUT_DIR/$NAME.dmg. Increase the build number or choose another output directory." >&2
    exit 1
fi
# Ad-hoc signing provides local code integrity, not verified publisher identity.
codesign --force --deep --sign - --entitlements "$PROJECT_ROOT/体脂秤/体脂秤Mac.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
mkdir -p "$BUILD_ROOT/image"
ditto "$APP" "$BUILD_ROOT/image/体脂秤.app"
ln -s /Applications "$BUILD_ROOT/image/Applications"
cp "$PROJECT_ROOT/docs/MAC_INSTALL.md" "$BUILD_ROOT/image/安装说明.md"
hdiutil create -quiet -volname 'AFU Scale' -srcfolder "$BUILD_ROOT/image" \
    -format UDZO "$OUTPUT_DIR/$NAME.dmg"
shasum -a 256 "$OUTPUT_DIR/$NAME.dmg" > "$OUTPUT_DIR/$NAME.dmg.sha256"
echo "Package: $OUTPUT_DIR/$NAME.dmg"
echo "Build workspace retained for inspection: $BUILD_ROOT"
