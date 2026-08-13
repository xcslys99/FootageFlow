# FootageFlow Roadmap

Roadmap items are intentions, not promises. Provider policies, platform rules, and available maintainer time may change implementation details.

## Completed Foundations

- macOS Apple Silicon edition
- Windows 11 x64 edition
- Shared cross-platform core
- Multi-provider footage search across 17 supported sources
- Pagination and **Load More**
- Advanced filters and downloadable-only filtering
- Local compound-query relevance ranking
- Ten-language interface and compound search
- Link Downloader for supported public media URLs
- Full-media and clip downloads
- Editing-compatible MP4 output
- Shared Download Manager
- Projects, favorites, search history, and download history
- Source sidecars and creator output metadata
- Provider-supplied rights and attribution metadata
- Openverse image/audio discovery
- Dailymotion video discovery
- Feedback & Community links
- GitHub Release update notifications
- Every-launch reminders for outdated installations

## Current Priorities

### 1. Project Export & Attribution ([#15](https://github.com/xcslys99/FootageFlow/issues/15))

- Export project metadata as Markdown, CSV, and JSON
- Export a human-readable HTML attribution report
- Generate creator, source, and license credits
- Preserve original source URLs and license URLs

### 2. Rights Audit ([#16](https://github.com/xcslys99/FootageFlow/issues/16))

- Show Rights Known, Attribution Required, Public Domain, and Rights Unknown
- Warn before exporting projects with incomplete rights metadata
- Never infer missing permissions

### 3. Project Backup & Cross-platform Import ([#17](https://github.com/xcslys99/FootageFlow/issues/17))

- Export a portable FootageFlow project manifest
- Import the manifest on macOS or Windows
- Preserve project structure, source metadata, search terms, and relative file references
- Do not bundle large media by default

### 4. Duplicate Detection ([#18](https://github.com/xcslys99/FootageFlow/issues/18))

- Detect duplicate Provider IDs
- Detect duplicate original and download URLs
- Detect duplicate local files by hash where practical
- Keep false positives low and allow user review

### 5. Accessibility & Keyboard Navigation ([#19](https://github.com/xcslys99/FootageFlow/issues/19))

- Improve VoiceOver and Windows screen-reader labels
- Add predictable keyboard navigation and visible focus indicators
- Add shortcuts for search, filters, projects, downloads, and update dialogs

## Planned Feature Releases

### v0.8.0 — Project Export & Attribution Update

This is a planned direction, not a delivery promise.

- Project attribution export
- Rights audit
- Project backup and cross-platform import
- Duplicate detection

### v0.9.0 — Research & Culture Update ([#20](https://github.com/xcslys99/FootageFlow/issues/20))

Planned research areas:

- The Metropolitan Museum of Art
- Art Institute of Chicago
- Wikipedia and Wikidata
- Crossref
- GDELT
- Media, Research, and All result modes

Every source requires a fresh review of its official API, rights metadata, authentication, rate limits, and platform policies before implementation.

## Later

- Signed and notarized releases when sustainable
- Optional local semantic search
- Provider extension or plugin architecture
- More user-driven Provider fixes
- Additional accessibility work

## Not Planned for the Core App

- Tracking or advertising
- Forced cloud accounts
- Forced subscriptions
- Mandatory paid AI APIs
- DRM bypass
- Browser-cookie theft
- Automatic publishing
