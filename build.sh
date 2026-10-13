#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${MARKEER_BUILD_DIR:-.build}"
FINAL="${MARKEER_APP_PATH:-dist/Markeer.app}"
STAGING=$(mktemp -d /private/tmp/markeer-package.XXXXXX)
DEST="$STAGING/Markeer.app"
mkdir -p "$BUILD" "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cmake -S Vendor/cmark-gfm -B "$BUILD/cmark" -DCMAKE_BUILD_TYPE=Release -DCMARK_SHARED=OFF -DCMARK_STATIC=ON -DCMARK_TESTS=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
cmake --build "$BUILD/cmark" -j 4
FLAGS=(-I Vendor/cmark-gfm/src -I Vendor/cmark-gfm/extensions -I "$BUILD/cmark/src" -I "$BUILD/cmark/extensions" -import-objc-header Sources/Bridge.h -module-cache-path "$BUILD/swift-cache" -framework AppKit -framework WebKit)
LIBS=("$BUILD/cmark/extensions/libcmark-gfm-extensions.a" "$BUILD/cmark/src/libcmark-gfm.a")
swiftc -O -target arm64-apple-macos13.0 -module-name Markeer "${FLAGS[@]}" Sources/Markdown.swift Sources/Document.swift Sources/Editor.swift Sources/main.swift "${LIBS[@]}" -o "$DEST/Contents/MacOS/Markeer"
cp Resources/Info.plist "$DEST/Contents/Info.plist"
cp Resources/*.js Resources/*.html Resources/*LICENSE "$DEST/Contents/Resources/"
cp Vendor/cmark-gfm/COPYING "$DEST/Contents/Resources/CMARK-LICENSE"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$DEST/Contents/Resources/"; fi
xattr -dr com.apple.FinderInfo "$DEST" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST"
swiftc -target arm64-apple-macos13.0 "${FLAGS[@]}" Sources/Markdown.swift Sources/Document.swift Sources/Editor.swift Tests/main.swift "${LIBS[@]}" -o "$BUILD/MarkeerTests"
"$BUILD/MarkeerTests" --parser-only
ditto "$DEST" "$FINAL"
ditto -c -k --sequesterRsrc --keepParent "$DEST" "${FINAL%.app}.zip"
printf '\nGebouwd en getest: %s\n' "$FINAL"
