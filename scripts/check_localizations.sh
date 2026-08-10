#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
english="$repo_root/Sources/FootageFlow/Resources/en.lproj/Localizable.strings"
chinese="$repo_root/Sources/FootageFlow/Resources/zh-Hans.lproj/Localizable.strings"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

extract_keys() {
  LC_ALL=C sed -nE 's/^"([^"]+)"[[:space:]]*=.*/\1/p' "$1" | sort -u
}

extract_keys "$english" > "$temp_root/en.keys"
extract_keys "$chinese" > "$temp_root/zh.keys"

comm -23 "$temp_root/en.keys" "$temp_root/zh.keys" | grep -v '^localization\.fallbackProbe$' > "$temp_root/missing-zh.keys" || true
comm -13 "$temp_root/en.keys" "$temp_root/zh.keys" > "$temp_root/missing-en.keys" || true

if [[ -s "$temp_root/missing-zh.keys" || -s "$temp_root/missing-en.keys" ]]; then
  [[ ! -s "$temp_root/missing-zh.keys" ]] || { printf 'Missing zh-Hans keys:\n'; sed 's/^/  /' "$temp_root/missing-zh.keys"; }
  [[ ! -s "$temp_root/missing-en.keys" ]] || { printf 'Missing English keys:\n'; sed 's/^/  /' "$temp_root/missing-en.keys"; }
  exit 1
fi

plutil -lint "$english" "$chinese" >/dev/null
printf 'LOCALIZATION_CHECK passed\n'
