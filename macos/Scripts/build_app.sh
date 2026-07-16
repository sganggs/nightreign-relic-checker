#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_ROOT="$ROOT/build"
APP="$BUILD_ROOT/夜幕验物.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release --product NightreignRelicChecker
ARM_BIN_DIR="$(swift build -c release --show-bin-path)"
X86_SCRATCH="$ROOT/.build-x86_64"
swift build -c release --product NightreignRelicChecker \
  --triple x86_64-apple-macosx13.0 \
  --scratch-path "$X86_SCRATCH"
X86_BIN_DIR="$(swift build -c release --show-bin-path --triple x86_64-apple-macosx13.0 --scratch-path "$X86_SCRATCH")"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

lipo -create \
  "$ARM_BIN_DIR/NightreignRelicChecker" \
  "$X86_BIN_DIR/NightreignRelicChecker" \
  -output "$CONTENTS/MacOS/NightreignRelicChecker"
cp "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Sources/NightreignRelicChecker/Resources/affixes.json" "$CONTENTS/Resources/affixes.json"
cp "$ROOT/Sources/NightreignRelicChecker/Resources/relics.json" "$CONTENTS/Resources/relics.json"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"

ICON_WORK="$BUILD_ROOT/icon"
rm -rf "$ICON_WORK"
mkdir -p "$ICON_WORK/AppIcon.iconset"
swift "$ROOT/Scripts/generate_icon.swift" "$ICON_WORK/AppIcon-1024.png"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
  px="${spec%% *}"
  name="${spec#* }"
  sips -z "$px" "$px" "$ICON_WORK/AppIcon-1024.png" --out "$ICON_WORK/AppIcon.iconset/$name" >/dev/null
done

iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$CONTENTS/MacOS/NightreignRelicChecker"
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "$APP"
