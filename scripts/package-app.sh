#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/QuotaPeek.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$ROOT"
swift build -c release --disable-sandbox --scratch-path "$BUILD_DIR"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILD_DIR/release/QuotaPeek" "$CONTENTS_DIR/MacOS/QuotaPeek"
cp "$ROOT/packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "Created $APP_DIR"
