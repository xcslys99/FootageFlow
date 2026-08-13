# Changelog

All notable FootageFlow changes are documented here.

## [0.7.4] - 2026-08-13

### Improved

- FootageFlow now checks for a newer stable GitHub Release asynchronously on every app launch when online
- Outdated installations show the current version, latest version, publication date, and the real Release Notes in a bounded scrollable dialog
- **Not Now** dismisses the automatic reminder only for the current session; a complete restart checks and reminds again if the installed version is still outdated
- Release Notes are converted from bounded Markdown to safe plain text shared by the macOS and Windows interfaces
- Startup network, timeout, rate-limit, and invalid-response failures remain silent; manual checks still show a friendly status
- README and the v0.5.0/v0.6.0 Release pages now direct legacy installations to upgrade manually once

### Security and privacy

- Update links are restricted to this repository's HTTPS Release path
- Update checks send only the installed FootageFlow version and standard GitHub API request headers
- FootageFlow never downloads, installs, or forces an update

### Validation

- Added semantic-version, stable-release, safe Release Notes, session dismissal/restart, silent startup failure, legacy-settings migration, and trusted-URL tests
- macOS and Windows release gates cover shared Core tests, native UI builds, packaging, clean install, startup, and uninstall

## [0.7.3] - 2026-08-12

### Fixed

- Clipboard media-link suggestions now remember every normalized URL already offered during the current app session, so ignored links do not reappear after another clipboard value; raw clipboard text is never persisted
- Added the same bounded clipboard check cooldown to macOS and Windows without enabling clipboard detection by default
- Editing-compatible downloads now retain a final `best` fallback for direct media whose extractor does not report resolution or codec metadata
- Vimeo OAuth 401 and equivalent logged-in-client failures are now shown as an access/login requirement instead of a generic download error
- Generic yt-dlp failures no longer incorrectly name YouTube when another media source failed

### Improved

- Openverse requests now explicitly set `mature=false`, and mature items are defensively removed if an upstream response still includes one
- Added a real creator-workflow smoke test for public YouTube, Dailymotion, and direct-media analysis, 10-second clip extraction, editing-compatible MP4 validation, fast-start, and source sidecars on both platform pipelines; hosted-runner YouTube blocks must be correctly classified rather than bypassed
- Removed stale v0.6.0 labels from the current English screenshots in both README files

### Validation

- 44 offline Swift unit and fixture tests pass
- The macOS creator-workflow smoke passed 12/12 checks using bundled yt-dlp and FFmpeg: YouTube, Dailymotion, and public direct media analyzed; the resulting clip measured 10 seconds and passed MP4, H.264, yuv420p, AAC, fast-start, and sidecar checks
- Windows CI is the release gate for WPF build, shared Swift core tests, the same real creator-workflow smoke, package assembly, installer, clean install, startup, and uninstall

## [0.7.2] - 2026-08-12

### Fixed

- Fixed `广州美食` being reduced to zero results when Apple Translation returned `Guangzhou delicacies`
- Translation and visual expansion phrases are now retrieval hints only and can no longer create new mandatory relevance concepts
- Added Guangzhou/Canton and food aliases for Cantonese cuisine, dim sum, yum cha, morning tea, street food, and seafood

### Added

- Added the shared `MultilingualQueryEngine` for English, Simplified Chinese, Traditional Chinese, Spanish, Brazilian Portuguese, Japanese, Korean, German, French, and Russian
- Every search now builds one complete compound query per language, with at most two input-language and two English visual expansions (14 total)
- Query records now preserve language, origin, and priority; old project and search-history data remains decodable
- Added **View all languages** to the macOS and Windows search editors; input-language and English queries remain visible by default
- Added language-aware ranking after semantic eligibility, plus global 12-request, official/public API two-request, and direct-search one-request concurrency limits

### Validation

- 43 offline unit and fixture tests pass, including Guangzhou concept coverage, ten canonical queries, language priority, legacy history decoding, and the v0.7.1 relevance regression set
- The real public-provider `广州美食` run retrieved 323 candidates; Provider order measured 7/20 relevant, while Balanced local ranking measured 20/20 relevant
- The installed macOS GUI displayed all ten editable language queries and returned real Guangzhou cuisine, dim sum, morning tea, seafood-market, and street-food results

## [0.7.1] - 2026-08-12

### Fixed

- Added a shared two-stage relevance pipeline so broad Provider matches no longer dominate composite searches
- Added local concept-group coverage and weighted title, tags, category, description, creator/channel, matched-query, and bounded Provider relevance scoring
- Filtered entity-only results such as Taiwan politics from Balanced `台湾美食` searches while retaining semantic matches such as Taipei beef noodle soup
- Preserved PeerTube tags/category, Internet Archive subjects/collection, Pixabay tags, and Wikimedia categories for local ranking

### Added

- Precise, Balanced, and Broad relevance modes on macOS and Windows, with Balanced as the persisted default
- Fixed Precision@20 relevance tests and a sanitized real-provider `--relevance-smoke` diagnostic
- Localized relevance controls in all ten interface languages

### Validation

- The fixed `台湾美食` evaluation returns 20 relevant items in the Top 20 without requiring the exact query phrase
- A live 122-candidate public-provider run removed all judged-irrelevant default results: the old provider order had 2 relevant items in its Top 20, while Balanced returned 14/14 relevant items
- Added concept proximity, conflicting-place, distractor-category, oversized-description, and noisy-tag safeguards for sparse archive metadata
- The installed macOS app returned 35 real `台湾美食` results; the first 20 were manually reviewed in the GUI and all 20 matched both core concepts

## [0.7.0] - 2026-08-12

### Added

- Cross-platform update checks against the latest official GitHub Release at app launch
- A native update dialog that shows the current/latest versions, publication date, and release notes before the user makes a choice
- **View Update** to open the official release page and **Remind Later** to defer the same release for 24 hours
- A manual **Check for Updates** action in macOS and Windows Settings
- Localized update UI and readable network, timeout, and rate-limit states in all ten interface languages

### Behavior and privacy

- Updates are never forced, silently downloaded, or automatically installed
- Startup failures remain unobtrusive; manual checks show a friendly status instead of a technical stack trace
- Only the current app version and normal HTTPS request metadata are sent to GitHub's public Releases API; no API key, project, search, download, clipboard, or local-path data is included
- The shared Swift core owns release parsing, semantic version comparison, official-URL validation, and reminder policy so macOS and Windows follow identical rules

### Compatibility note

- v0.6.0 and earlier cannot receive an in-app update notice retroactively because those binaries do not contain an update checker. One manual upgrade to v0.7.0 is required before future releases can be discovered in the app.

## [0.6.0] - 2026-08-12

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
