#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app="${1:-$project_root/dist/FootageFlow.app}"
binary="$app/Contents/MacOS/FootageFlow"

[[ -x "$binary" ]]

if strings "$binary" | LC_ALL=C grep -Eq '/Users/|/Volumes/|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'; then
  printf 'BINARY_PRIVACY_SCAN failed: personal path or credential-like data found\n' >&2
  exit 1
fi

printf 'BINARY_PRIVACY_SCAN passed\n'
