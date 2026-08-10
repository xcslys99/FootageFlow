#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="${1:-$PROJECT_DIR/dist/FootageFlow.app}"
"$APP_DIR/Contents/MacOS/FootageFlow" --self-test
"$APP_DIR/Contents/MacOS/FootageFlow" --live-smoke
"$PROJECT_DIR/scripts/binary_privacy_scan.sh" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
