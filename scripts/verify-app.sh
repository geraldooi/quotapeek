#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/QuotaPeek.app"
BINARY="$APP_DIR/Contents/MacOS/QuotaPeek"
CLAUDE_BRIDGE="$APP_DIR/Contents/Helpers/QuotaPeekClaudeBridge"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
EXPECTED_ICON_FILE="QuotaPeek.icns"

test -d "$APP_DIR"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" = "$EXPECTED_VERSION"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_DIR/Contents/Info.plist")"
test "$ICON_FILE" = "$EXPECTED_ICON_FILE"
test -f "$APP_DIR/Contents/Resources/$ICON_FILE"
test -f "$APP_DIR/Contents/Resources/BrandIcons/codex.png"
test -f "$APP_DIR/Contents/Resources/BrandIcons/claude-code.png"
test -f "$APP_DIR/Contents/Resources/BrandIcons/NOTICE.md"
test -x "$CLAUDE_BRIDGE"

ARCHITECTURES="$(lipo -archs "$BINARY")"
case " $ARCHITECTURES " in
    *" arm64 "*) ;;
    *) echo "Missing arm64 architecture" >&2; exit 1 ;;
esac

BRIDGE_ARCHITECTURES="$(lipo -archs "$CLAUDE_BRIDGE")"
case " $BRIDGE_ARCHITECTURES " in
    *" arm64 "*) ;;
    *) echo "Claude bridge is missing arm64 architecture" >&2; exit 1 ;;
esac
case " $BRIDGE_ARCHITECTURES " in
    *" x86_64 "*) ;;
    *) echo "Claude bridge is missing x86_64 architecture" >&2; exit 1 ;;
esac
case " $ARCHITECTURES " in
    *" x86_64 "*) ;;
    *) echo "Missing x86_64 architecture" >&2; exit 1 ;;
esac

codesign --verify --deep --strict "$APP_DIR"
echo "Verified QuotaPeek $EXPECTED_VERSION ($ARCHITECTURES)"
