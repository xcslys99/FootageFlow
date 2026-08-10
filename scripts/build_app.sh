#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/FootageFlow.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$PROJECT_DIR/.build/FootageFlow.iconset"
TOOLS_DIR="$RESOURCES_DIR/Tools"

cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$TOOLS_DIR"
cp "$BIN_DIR/FootageFlow" "$MACOS_DIR/FootageFlow"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "$PROJECT_DIR/Sources/FootageFlow/Resources/"*.lproj "$RESOURCES_DIR/"
YT_DLP_PATH="$("$PROJECT_DIR/scripts/fetch_yt_dlp.sh")"
cp "$YT_DLP_PATH" "$TOOLS_DIR/yt-dlp"
chmod 755 "$TOOLS_DIR/yt-dlp"

swiftc "$PROJECT_DIR/Tools/IconMaker.swift" -o "$PROJECT_DIR/.build/IconMaker" -framework AppKit
"$PROJECT_DIR/.build/IconMaker" "$PROJECT_DIR/.build/icon-1024.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PROJECT_DIR/.build/icon-1024.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$PROJECT_DIR/.build/icon-1024.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
