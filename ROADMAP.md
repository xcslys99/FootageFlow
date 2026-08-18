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
- Project attribution reports in Markdown, CSV, JSON, and HTML
- Credits generation and provider-reported rights audit
- Portable `.footageflowproject` backup and cross-platform import
- Local-first duplicate detection with user decisions and lazy SHA-256
- PNG contact-sheet generation

## Current Priorities

### Accessibility & Keyboard Navigation ([#19](https://github.com/xcslys99/FootageFlow/issues/19))

- Improve VoiceOver and Windows screen-reader labels
- Add predictable keyboard navigation and visible focus indicators
- Add shortcuts for search, filters, projects, downloads, and update dialogs

## Planned Feature Releases

### v0.8.0 — Project Export & Attribution Update

Delivered in v0.8.0:

- Project attribution export and concise/detailed credits
- Rights audit with non-blocking export review warning
- Project backup and cross-platform import
- Duplicate detection with user decisions
- Contact-sheet generation

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
