#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/QuotaPeek.app"
CONTENTS_DIR="$APP_DIR/Contents"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

cd "$ROOT"
swift build \
    -c release \
    --arch arm64 \
    --disable-sandbox \
    --scratch-path "$BUILD_DIR/arm64"
swift build \
    -c release \
    --arch x86_64 \
    --disable-sandbox \
    --scratch-path "$BUILD_DIR/x86_64"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
lipo -create \
    "$BUILD_DIR/arm64/arm64-apple-macosx/release/QuotaPeek" \
    "$BUILD_DIR/x86_64/x86_64-apple-macosx/release/QuotaPeek" \
    -output "$CONTENTS_DIR/MacOS/QuotaPeek"
cp "$ROOT/packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
