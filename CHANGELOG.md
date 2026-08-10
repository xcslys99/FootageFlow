# Changelog

All notable FootageFlow changes are documented here.

## [Unreleased]

## [0.2.0] - 2026-08-10

### Added

- Native Windows 11 x64 WPF application with a self-contained installer; end users do not need Python, Node.js, Swift, or .NET
- Shared Swift Core Host for provider behavior, normalized metadata, license rules, keyword processing, source sidecars, and project persistence
- Windows Credential Manager storage for Pexels, Pixabay, and YouTube API keys
- Windows project library, favorites, search history, bounded download queue, cancel/retry, source sidecars, settings, preview, and Explorer integration
- English and Simplified Chinese Windows interface with English first-launch default, immediate switching, and persisted language selection
- Optional official API mode for Pexels and Pixabay, selected automatically when a local key exists
- Best-effort direct search for Pexels and Pixabay when no API key is configured
- Explicit provider modes, capabilities, connection status, and a Sources / Providers settings section
- Local yt-dlp best-effort YouTube search and download with bounded retries and friendly failure states
- License-known-only filtering and direct-search license uncertainty handling

### Changed

- First launch now opens directly into FootageFlow without requiring API configuration
- Provider failures remain isolated and present rate limits, temporary blocks, unavailable videos, and regional restrictions in user-friendly language
- API keys can be added, replaced, tested, and removed without displaying or logging their full value

### Known limitations

- The Windows installer is not code-signed and Microsoft Defender SmartScreen may show an unrecognized-app warning. Verify the attached SHA-256 checksum before opening it.
- The macOS build remains Ad Hoc signed and is not notarized.
- Windows 11 x64 is the supported Windows target. Windows 10 has not completed release validation.
- YouTube search and downloading without a Data API key are best-effort and can fail because of provider restrictions or upstream changes.
- Pexels and Pixabay direct searches are best-effort; optional API keys provide a more reliable mode.
- Live official-API smoke tests run only when repository secrets are present; all API-key modes are also covered by fixed offline fixtures.

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
- YouTube downloading was not included in v0.1.0; best-effort support is under development for the next feature release.
- Embedded preview depends on the source exposing a compatible stream.
- Windows support is planned after macOS v0.1.0 stabilizes.
