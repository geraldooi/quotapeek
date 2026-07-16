#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/QuotaPeek.app"
BINARY="$APP_DIR/Contents/MacOS/QuotaPeek"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

test -d "$APP_DIR"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" = "$EXPECTED_VERSION"

ARCHITECTURES="$(lipo -archs "$BINARY")"
case " $ARCHITECTURES " in
    *" arm64 "*) ;;
    *) echo "Missing arm64 architecture" >&2; exit 1 ;;
esac
case " $ARCHITECTURES " in
    *" x86_64 "*) ;;
    *) echo "Missing x86_64 architecture" >&2; exit 1 ;;
esac

codesign --verify --deep --strict "$APP_DIR"
echo "Verified QuotaPeek $EXPECTED_VERSION ($ARCHITECTURES)"
