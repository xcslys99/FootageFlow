#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="${1:-$PROJECT_DIR/dist/FootageFinder.app}"
"$APP_DIR/Contents/MacOS/FootageFinder" --self-test
"$APP_DIR/Contents/MacOS/FootageFinder" --live-smoke
codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
