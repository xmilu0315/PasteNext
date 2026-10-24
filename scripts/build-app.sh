#!/bin/zsh
# Builds PasteNext.app (ad-hoc signed) and packages it as a macOS .dmg
# with a drag-and-drop guide background.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
DIST="$ROOT/Dist"
TMP_BUILD="$(mktemp -d /tmp/pastenext-build.XXXXXX)"
APP="$TMP_BUILD/PasteNext.app"
trap 'rm -rf "$TMP_BUILD"' EXIT

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$DIST/PasteNext-$VERSION.dmg"

# ---- Universal binary (Apple Silicon + Intel) --------------------------
# The app is built twice and merged with lipo so it also runs on Intel Macs.
MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"
swift build --disable-sandbox --package-path "$ROOT" -c release
swift build --disable-sandbox --package-path "$ROOT" -c release \
    --scratch-path "$ROOT/.build-x86" \
    --triple x86_64-apple-macosx13.0 --sdk "$MACOS_SDK"

ARM_BIN="$BUILD/release/PasteNext"
X86_BIN="$ROOT/.build-x86/release/PasteNext"
UNIVERSAL="$TMP_BUILD/PasteNext-universal"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNIVERSAL"
echo "architectures: $(lipo -archs "$UNIVERSAL")"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$UNIVERSAL" "$APP/Contents/MacOS/PasteNext"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/donate-wechat.png" "$APP/Contents/Resources/donate-wechat.png"
cp "$ROOT/Resources/donate-alipay.png" "$APP/Contents/Resources/donate-alipay.png"
chmod +x "$APP/Contents/MacOS/PasteNext"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

"$APP/Contents/MacOS/PasteNext" --self-test

# ---- DMG with a drag-and-drop guide background ----
# The background art (app icon on the left, Applications folder on the right,
# arrow in between) is generated from the same vector sources as the app icon.
# Only the 1x art is used: Finder derives the content area from the
# background's pixel size, so a 2x companion would double the layout.
swift "$ROOT/scripts/make-dmg-background.swift" "$ROOT" >/dev/null
rm -f "$ROOT/Resources/dmg-background@2x.png"

rm -f "$DMG"
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
    print -u2 "error: node is required to build the DMG background layout"
    exit 1
fi
# The DMG helper writes the .DS_Store with the `ds-store` package; install it
# on demand so a fresh clone can build without a separate setup step.
if [ ! -d "$ROOT/scripts/dmg/node_modules/ds-store" ]; then
    print "installing the DMG build dependencies..."
    (cd "$ROOT/scripts/dmg" && npm install --silent)
fi
# The .DS_Store (background alias, window bounds, icon positions) is written
# by the node helper, which uses the same format Finder reads.
"$NODE_BIN" "$ROOT/scripts/dmg/build.mjs" \
    --app "$APP" \
    --background "$ROOT/Resources/dmg-background.png" \
    --out "$DMG" \
    --title "PasteNext $VERSION" \
    --width 640 --height 330 \
    --app-x 124 --app-y 100 \
    --apps-x 515 --apps-y 100

hdiutil verify "$DMG" >/dev/null

# Render a proof of the window layout straight from the built image, so the
# icon positions can be checked without opening the disk image.
VERIFY_MOUNT="$(mktemp -d /tmp/pastenext-verify.XXXXXX)"
if hdiutil attach "$DMG" -mountpoint "$VERIFY_MOUNT" -nobrowse -quiet 2>/dev/null; then
    swift "$ROOT/scripts/dmg/verify-layout.swift" "$ROOT" "$VERIFY_MOUNT" >/dev/null 2>&1 || true
    hdiutil detach "$VERIFY_MOUNT" -force -quiet 2>/dev/null || true
fi
rm -rf "$VERIFY_MOUNT"

print -r -- "$DMG"
