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
APP="$BUILD_ROOT/build/Build/Products/Release-maccatalyst/WeighTrace.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
NAME="AFU-Scale-Mac-$VERSION-$BUILD-test"
APP_OUTPUT="$OUTPUT_DIR/WeighTrace-$VERSION-$BUILD-test.app"
# Keep the legacy download prefix so older clients can still discover updates.
if [[ -e "$OUTPUT_DIR/$NAME.dmg" || -e "$APP_OUTPUT" ]]; then
    echo "Output already exists for $VERSION ($BUILD). Increase the build number or choose another output directory." >&2
    exit 1
fi
# Ad-hoc signing provides local code integrity, not verified publisher identity.
# Catalyst's generated .icns may contain only small fallback sizes; retain a full
# 16–1024px fallback in distributed builds, before applying the package signature.
cp "$PROJECT_ROOT/design/WeighTrace.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - --entitlements "$PROJECT_ROOT/体脂秤/体脂秤Mac.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto "$APP" "$APP_OUTPUT"
mkdir -p "$BUILD_ROOT/image"
ditto "$APP_OUTPUT" "$BUILD_ROOT/image/WeighTrace.app"
ln -s /Applications "$BUILD_ROOT/image/Applications"
cp "$PROJECT_ROOT/docs/MAC_INSTALL.md" "$BUILD_ROOT/image/安装说明.md"
cp "$PROJECT_ROOT/LICENSE" "$BUILD_ROOT/image/LICENSE"
REVISION=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
SOURCE_STATE=clean
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=normal)" ]]; then
    SOURCE_STATE='contains uncommitted changes; the commit link alone does not reproduce this build'
fi
printf 'WeighTrace %s (%s)\nSource commit: %s\nBuild source state: %s\nSource: https://github.com/Xuan-lprk/WeighTrace/tree/%s\nLicense: GNU GPL v3.0 (see LICENSE)\n' \
    "$VERSION" "$BUILD" "$REVISION" "$SOURCE_STATE" "$REVISION" > "$BUILD_ROOT/image/SOURCE.txt"
hdiutil create -quiet -volname 'WeighTrace' -srcfolder "$BUILD_ROOT/image" \
    -format UDZO "$OUTPUT_DIR/$NAME.dmg"
shasum -a 256 "$OUTPUT_DIR/$NAME.dmg" > "$OUTPUT_DIR/$NAME.dmg.sha256"
echo "Package: $OUTPUT_DIR/$NAME.dmg"
echo "Runnable app: $APP_OUTPUT"
echo "Build workspace retained for inspection: $BUILD_ROOT"
