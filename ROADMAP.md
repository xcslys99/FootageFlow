# FootageFlow Roadmap

Roadmap items are intentions, not promises. Provider policies, platform rules, and available maintainer time may change implementation details.

## Completed Foundations

- macOS Apple Silicon edition
- Windows 11 x64 edition
- Shared cross-platform core
- Multi-provider footage search across 22 supported sources
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
- Research & Culture workspace: Media / Research / All, references, notes, citations, and related-media discovery
- Workspace dashboard, local-only Global Search, Saved Searches, Smart Collections, Provider Health, Command Palette, and keyboard/accessibility improvements
- Dareful public direct search/download, ESA Multimedia discovery, and official-search discovery entries for Mazwai, DVIDS, and British Pathé

## Current Priorities

### Accessibility & Keyboard Navigation ([#19](https://github.com/xcslys99/FootageFlow/issues/19))

v0.10.0 provides the first cross-platform accessibility and keyboard-navigation foundation:

- VoiceOver and Windows screen-reader labels for the primary workspace and media actions
- Predictable keyboard navigation, native visible focus, Command Palette, Global Search, and a discoverable shortcut reference
- Local Workspace dashboards, Saved Searches, Smart Collections, and manual Provider Health checks

Issue #19 remains open for continued manual VoiceOver/Narrator verification across the broader creator workflow.

## Planned Feature Releases

### v0.11.0 — No-key Provider Update

Delivered in v0.11.0:

- Dareful public direct search with CC BY 4.0 attribution and handoff to the existing Download Manager
- ESA Multimedia public media discovery with per-item rights kept unknown until checked on the original page
- Mazwai, DVIDS, and British Pathé as limited-discovery providers with official-search actions rather than restricted-page scraping
- Shared macOS/Windows provider modes, settings migration, capability display, and failure isolation for all five sources

### v0.10.0 — Workspace & Accessibility Update ([#19](https://github.com/xcslys99/FootageFlow/issues/19))

Delivered in v0.10.0:

- Local-only Global Search and a keyboard-first Command Palette
- Saved Searches, project dashboard summaries, dynamic Smart Collections, and user-triggered Provider Health
- Shared macOS/Windows workspace data and ten-language UI coverage

### v0.8.0 — Project Export & Attribution Update

Delivered in v0.8.0:

- Project attribution export and concise/detailed credits
- Rights audit with non-blocking export review warning
- Project backup and cross-platform import
- Duplicate detection with user decisions
- Contact-sheet generation

### v0.9.0 — Research & Culture Update ([#20](https://github.com/xcslys99/FootageFlow/issues/20))

Delivered in v0.9.0:

- Media / Research / All search modes
- Wikipedia, Wikidata, The Met, Art Institute of Chicago, Crossref, and GDELT public research discovery
- Local Research Notes, citation copy, source refresh, and Find Related Media
- Research References and Combined Project Report export
- Portable project schema v2 with backward-compatible v1 import

Research providers remain reference/discovery sources. They do not grant media rights, bypass paywalls, download article full text, or turn a visible preview into a reusable asset.

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
