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

### v0.13.0 — Smart Duplicate Review (in development)

- Cross-provider search-result grouping after the existing relevance and filter gates, with all original cards retained
- Shared deterministic and corroborated-metadata evidence, plus bounded local thumbnail dHash as a background enhancement
- Grouped/All Results controls, default-on detection, a recommended version for workflow convenience, and ten-language accessibility labels
- macOS and Windows regression, packaging, and manual screen-reader verification before a release

This is not a published release. A suggested version never conveys rights from one Provider to another.

### Accessibility & Keyboard Navigation ([#19](https://github.com/xcslys99/FootageFlow/issues/19))

v0.10.0 provided the first cross-platform accessibility and keyboard-navigation foundation. v0.12.0 completes the planned keyboard paths and semantic coverage:

- VoiceOver and Windows Narrator labels for filters, result cards, Projects, Download Manager, Settings, Link Downloader, and update dialogs
- Predictable keyboard navigation, visible focus, Command Palette, Global Search, a safe **Clear Filters** action, and Windows focus restoration after transient panels
- Ten-language accessibility strings and a real-device manual VoiceOver/Narrator acceptance checklist

Future accessibility reports remain welcome; automated checks do not replace actual VoiceOver/Narrator testing on supported systems.

### Compound Search Relevance Fix (v0.12.1)

v0.12.1 fixes a compound-query regression without changing Provider, download, project, or accessibility workflows:

- Required places and proper nouns are preserved even when they are not yet in the curated lexicon
- Ten-language canonical requests never reduce a compound topic to a subject-only query
- Default **Balanced** relevance requires metadata evidence for every required concept; **Broad** remains the explicit weak-related-results mode

## Planned Feature Releases

### v0.12.1 — Compound Search Relevance Fix

Delivered in v0.12.1:

- Xi'an food and Berlin night-scene multilingual mappings and result gates
- Deterministic unknown CJK and Latin entity preservation
- Cross-platform regression coverage for location-plus-topic false positives

### v0.12.0 — Accessibility & Keyboard Navigation Update ([#19](https://github.com/xcslys99/FootageFlow/issues/19))

Delivered in v0.12.0:

- Keyboard-only flows for filtering, result actions, project work, downloads, settings, and modal workflows
- Clear focus feedback on Windows and restored focus after transient Workspace panels
- Expanded VoiceOver/Narrator semantics and state announcements, including the notification-only updater
- New accessibility copy localized into all ten supported interface languages

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
