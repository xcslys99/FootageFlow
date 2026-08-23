# Workspace

FootageFlow v0.10.0 connects existing local creator tools without introducing a cloud account or a second library.

## Command Palette

Open **Command Palette** with `⌘K` on macOS or `Ctrl+K` on Windows. Type part of an action name, use the arrow keys, press Enter to run it, or Escape to close it. It offers only FootageFlow actions that already exist, including search modes, projects, downloads, saved searches, source status, settings, and update checks.

## Local Global Search

Open **Global Search** with `⌘⇧G` on macOS or `Ctrl+Shift+G` on Windows. It searches only metadata stored by FootageFlow on the current device:

- Projects and project media
- Favorites and download history
- Search history and saved searches
- Research references and local notes
- Local-file records

The in-memory index is rebuilt from the existing local database when its metadata changes. It never scans arbitrary disks, uploads records, or indexes API keys, cookies, passwords, authorization headers, tokens, clipboard contents, or signed-URL values.

## Saved Searches and Smart Collections

**Save Search** stores the query, scope, filters, sources, relevance mode, and visible query configuration on this device. You can run, rename, duplicate, or remove saved searches from Workspace. Names remain separate: a duplicate is named `Search name (2)` instead of replacing the original.

Smart Collections are dynamic views over existing records; they do not copy media or change source metadata. They include downloaded media, recent downloads and favorites, unknown rights, attribution-required records, research without notes, recent research, missing local media, and possible repeated records.

## Project Dashboard and Provider Status

Each selected project shows factual counts for media, downloads, research, rights that need review, attribution-required items, missing local media, and possible duplicates. Project Actions remain the place for rights audit, credits, export, duplicate review, backup, and contact sheets.

**Provider Status** reflects recent checks on the current device only. Testing a provider sends one small, normal provider connection request; it is user-initiated, bounded to two simultaneous tests, and is never performed automatically at startup. Status is not an uptime promise.
