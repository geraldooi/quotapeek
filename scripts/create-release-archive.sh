#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
ARCHIVE="$ROOT/dist/QuotaPeek-$VERSION.zip"

rm -f "$ARCHIVE"
ditto \
    -c \
    -k \
    --keepParent \
    --norsrc \
    --noextattr \
    "$ROOT/dist/QuotaPeek.app" \
    "$ARCHIVE"
shasum -a 256 "$ARCHIVE"
