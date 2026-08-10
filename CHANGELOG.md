# Changelog

All notable FootageFlow changes are documented here.

## [0.1.0] - 2026-08-10

### Added

- Native macOS SwiftUI application for Apple Silicon and macOS 15+
- Pexels video/photo search
- Pixabay video/photo search
- Wikimedia Commons image/video search and license metadata
- Internet Archive archival search, item metadata, downloadable file resolution, and unknown-rights handling
- YouTube Data API search for source discovery
- Concurrent progressive provider search with provider-specific failures
- Filters, sorting, deduplication, search cache, and search history
- English and Simplified Chinese UI with English first-launch default
- Optional Apple Translation-assisted Chinese-to-English keyword generation with rule fallback
- Project library, favorites, script segmentation, and bounded batch search
- Preview, download queue, progress, speed, cancel, retry, and download history
- `.source.txt` and `.source.json` license/source sidecars
- Secure credential storage, redacted logs, URL validation, and bounded network retry behavior
- Offline self-tests, fixed provider fixtures, linting, secret scan, and macOS CI

### Known limitations

- v0.1.0 is Ad Hoc signed and not notarized.
- The current release is Apple Silicon only.
- YouTube videos are not downloadable through FootageFlow.
- Embedded preview depends on the source exposing a compatible stream.
- Windows support is planned after macOS v0.1.0 stabilizes.
