#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
tool_dir="$project_dir/.build/tools"
tool_path="$tool_dir/yt-dlp"
version="2026.07.04"
expected_sha256="498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b"
download_url="https://github.com/yt-dlp/yt-dlp/releases/download/$version/yt-dlp_macos"

mkdir -p "$tool_dir"

verify_tool() {
  [[ -f "$1" ]] || return 1
  [[ "$(shasum -a 256 "$1" | awk '{print $1}')" == "$expected_sha256" ]]
}

if verify_tool "$tool_path"; then
  chmod 755 "$tool_path"
  print -r -- "$tool_path"
  exit 0
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/footageflow-ytdlp.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
temporary_tool="$temporary_dir/yt-dlp"

curl --fail --location --silent --show-error --retry 2 --retry-delay 2 \
  --connect-timeout 20 --max-time 300 \
  --output "$temporary_tool" "$download_url"

if ! verify_tool "$temporary_tool"; then
  print -u2 -- "yt-dlp checksum verification failed"
  exit 1
fi

chmod 755 "$temporary_tool"
mv "$temporary_tool" "$tool_path"
print -r -- "$tool_path"
