#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

scripts/check_localizations.sh
scripts/check_markdown_links.sh
swift format lint --strict --recursive Sources Tests Package.swift
printf 'LINT passed\n'
