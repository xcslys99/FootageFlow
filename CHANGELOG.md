# Changelog

All notable FootageFlow changes are documented here.

## [Unreleased]

### Added

- Validated full-media or start/end clip downloads through the existing Link Downloader and Download Manager
- Rule-based Smart Search Expansion with visible, editable queries, provider budgets, and no paid AI dependency
- Original, editing-compatible H.264/AAC MP4, and M4A audio output presets
- Optional, foreground-only, local clipboard media-link detection with cooldown, ignore, and disable controls
- Openverse public image/audio search with pagination and item-specific license/attribution metadata
- Dailymotion public video discovery with pagination, unknown-rights handling, and Open Original behavior

### Improved

- Creator output and clip metadata now persist in filenames, source sidecars, queue rows, and download history
- Bundled FFmpeg/FFprobe support on macOS and Windows, including macOS system HTTPS support for HLS media
- Keyword coverage, provider-specific query budgets, cross-query de-duplication, and result ranking
- Cross-platform Link Downloader controls and Download Manager parity

### Security

- Clipboard detection is disabled by default, runs only while the app is active, and never uploads or logs clipboard contents
- Clip/download processing still ignores browser cookies and user yt-dlp configuration and never bypasses DRM, sign-in, private, paid, or regional controls
- FFmpeg and x264 are built or fetched from checksum-pinned GPL-compatible sources with bundled notices

## [0.5.0] - 2026-08-11

### Added

- Provider-owned pagination and cross-platform Load More with retry-safe continuation state
- PeerTube/SepiaSearch public discovery, Coverr official API mode, and Vimeo official discovery mode
- Non-scraping official-search discovery entries for Videvo, Videezy, and Mixkit
- Cross-platform Link Downloader for public media URLs with batch analysis, actual format/subtitle choices, and the existing Download Manager
- Feedback & Community shortcuts for GitHub bug reports, feature ideas, Q&A, repository, and releases

### Improved

- Search result volume, cumulative provider counts, de-duplication, and isolation of failed next-page requests
- yt-dlp progress and speed reporting, friendly unsupported/login/region/rate-limit failures, and safe cancellation/retry
- Provider capability and settings parity across macOS and Windows
- Cross-platform thumbnail reliability with provider-aware URL normalization, PeerTube instance resolution, ordered fallback candidates, response validation, short-lived failure caching, loading state, and explicit retry

### Security

- Link analysis ignores user configuration, does not import browser cookies, rejects embedded URL credentials and sensitive query parameters, blocks local/private-network addresses, and does not bypass DRM, sign-in, private, paid, or regional access controls
- DRM-marked formats are excluded from format choices, and source sidecars redact sensitive URL query values
- Feedback links exclude credentials, private paths, search/download history, filenames, and project content

## [0.4.0] - 2026-08-10

### Added

- Traditional Chinese, Spanish, Brazilian Portuguese, Japanese, Korean, German, French, and Russian interfaces on macOS and Windows
- A localized recommendation below Quick Search explaining that National Archives, Europeana, and YouTube work better with their free official APIs, with a direct path to provider settings
- Cross-platform locale resource validation, placeholder validation, fallback tests, persistence tests, and Windows installer language support

### Changed

- The language switcher now exposes ten native-language names while preserving English as the first-launch default
- macOS and Windows packaging now include every supported locale automatically

### Known limitations

- The Windows installer is not code-signed and the macOS app is Ad Hoc signed but not notarized.
- National Archives and Europeana still require a user key for complete in-app search; YouTube keyless search and downloading remain best-effort.
- Provider-supplied rights metadata may be incomplete; unknown information must be checked on the original source page.

## [0.3.0] - 2026-08-10

### Added

- NASA Image and Video Library through the official public search and asset APIs
- Library of Congress film/video, photo, and audio discovery through the official public JSON API
- National Archives Catalog API integration with secure user-key storage and a non-scraping limited mode
- Europeana Search API integration with secure user-key storage and a non-scraping limited mode
- Advanced source, media type, year, duration, resolution, rights, and downloadability filters
- Prominent Downloadable Only filter based on direct download availability
- Multi-select, Select All Visible, batch download, add to existing/new project, copy source information, and clear selection
- Per-result Copy Source and Copy Attribution actions
- Structured `RightsInfo`, explicit direct/conditional/unavailable download state, and backward-compatible v0.2 metadata decoding
- Retry Failed action for batch download recovery

### Improved

- Provider capability and mode presentation across macOS and Windows
- Progressive nine-provider result handling and provider-specific rate limiting
- Rights metadata normalization without inferring Public Domain from provider identity
- API/keyless selection, secure NARA/Europeana credentials, and public/limited-mode messaging
- Search-cache policy enforcement for National Archives
- Cross-platform feature parity and localization coverage

### Known limitations

- Full in-app National Archives and Europeana search requires the user's own API key; without one, FootageFlow opens the official search site.
- The Windows installer is not code-signed and the macOS app is Ad Hoc signed but not notarized.
- Windows 11 x64 is supported; Windows 10 has not completed release validation.
- YouTube, Pexels, and Pixabay best-effort modes can be limited by upstream provider changes.
- Provider-supplied rights metadata may be incomplete; unknown information must be checked on the original source page.

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
