# Changelog

All notable FootageFlow changes are documented here.

## Unreleased

## [0.13.0] - 2026-09-17

### Smart Duplicate Review

- Added cross-provider search-result duplicate groups while preserving every original result and its individual rights, source, and actions
- Reused the existing project URL canonicalization and duplicate evidence normalization, and retained cross-provider search hits previously dropped before review
- Added exact, likely, and possible evidence levels; a recommended version is selected for workflow convenience only, never as legal advice
- Added bounded, local thumbnail dHash analysis after the initial results appear, with metadata-only fallback on decoding or network failure
- Added Grouped / All Results controls, default-on detection and collapse settings, and ten-language labels for macOS and Windows
- Added fixed duplicate fixtures, false-positive checks, rights-isolation tests, and 100/500/1000-result performance coverage

### Creator workflow usability

- Switching a completed media search between Video, Image, Audio, and All now requests the newly selected media type instead of displaying a false empty result set
- Coalesced identical query text before each Provider request while keeping all ten editable language slots
- Replaced the overflowing 22-source checkbox strip with an expandable source selector, and grouped discovery-only notices instead of presenting them as repeated failures
- Kept the Windows source selector collapsed by default so search-result cards retain useful vertical space in smaller windows
- Public sources that reject a request no longer incorrectly report an invalid API key; keyless discovery-only sources no longer suggest configuring an unavailable key
- Made macOS project details scrollable and kept the project list a useful width
- Added an explicit project picker to the Link Downloader on both desktop platforms; macOS now shows a loading indicator while a link is being analyzed
- Scoped completed-download reuse to the same project and destination, so a previous copy cannot silently prevent saving the same media into a different project
- Refreshed the checksummed Windows FFmpeg archive after the previous upstream autobuild asset disappeared, restoring self-contained packaging

## [0.12.1] - 2026-08-26

### Fixed

- Fixed compound-search planning that could drop an unrecognized CJK place or proper noun after recognizing a broad subject; a search such as `西安美食` no longer generates subject-only requests such as `cuisine` or `food`
- Added complete ten-language Xi'an and Berlin query mappings, including location-aware filtering for Xi'an food and Berlin night-scene searches
- Balanced relevance mode now requires every required concept to be evidenced by source metadata, preventing a result from passing on a location or subject match alone

### Improved

- Added deterministic unknown-entity preservation for CJK and Latin compound queries, with translation-derived spellings treated only as aliases for the original required entity
- Added cross-platform regression coverage for Xi'an food, Berlin night scenes, unknown-place compound searches, and broad-subject false positives
- Kept Library of Congress requests isolated and cancellable while allowing its public catalog a slightly longer provider-specific response window
- Pinned the Windows FFmpeg dependency to an immutable BtbN build and verified SHA-256 instead of the moving `latest` asset

## [0.12.0] - 2026-08-26

### Improved

- Completed keyboard-first paths across Quick Search, filters, result-card actions, Projects, Download Manager, Settings, Command Palette, Global Search, Link Downloader, and update dialogs on macOS and Windows
- Added **Clear Filters**, which restores normal search filters without removing the current query, keyword plan, project selection, or already loaded results
- Added explicit VoiceOver and Windows Narrator/UI Automation labels for navigation, source toggles, link input, project lists, result counts, download state/progress, thumbnail retry, and icon-only actions
- Added a visible accent focus outline for Windows keyboard controls and restoration to the invoking control when Command Palette or Global Search closes
- Made the update dialog keyboard-complete: initial focus is **Not Now**, Escape cancels, the Release Notes area is labelled and reachable, and **View Update** is clearly described as opening the official Release page
- Added all new accessibility strings in English, 简体中文, 繁體中文, Español, Português (Brasil), 日本語, 한국어, Deutsch, Français, and Русский

### Correctness and validation

- Kept the updater notification-only: it does not display in-app download progress, silently download, install, skip a version permanently, or force an update
- Added regression tests for localized accessibility copy and safe filter reset behavior; expanded the Windows platform test coverage for the same ten-language labels
- Added a release-candidate manual checklist for real VoiceOver and Narrator verification; automated tests validate declarations and behavior but do not claim to replace a human screen-reader check

## [0.11.0] - 2026-08-25

### Added

- Five no-key footage-provider entries shared by macOS and Windows: Dareful, ESA Multimedia, Mazwai, DVIDS, and British Pathé
- Dareful bounded public direct search with HLS preview/download handoff to the existing bundled yt-dlp queue, CC BY 4.0 attribution, and normal source sidecars
- ESA Multimedia bounded public media discovery for image/video results, with original-page opening and rights left unknown unless the source explicitly supplies them
- Official-search discovery actions for Mazwai, DVIDS, and British Pathé, so creators can keep those sources in one provider list even where the current public sites restrict automated result retrieval
- A legacy-safe settings migration that enables all five new no-key sources for existing installations without changing user API keys

### Safety and rights

- Direct-search adapters do not bypass CAPTCHA, WAF challenges, login, cookies, paywalls, or access controls
- Mazwai, DVIDS, and British Pathé remain discovery-only in FootageFlow; no direct-download button is inferred from a searchable source
- ESA rights remain item-specific and unknown until verified on the original page; Dareful results retain their source-supplied CC BY 4.0 attribution requirement

### Platforms and validation

- The shared Swift Core supplies the same five provider IDs, capabilities, settings migration, source-sidecar behavior, and failure isolation to macOS and Windows
- Added direct-search parser fixtures and capability/mode coverage for Dareful and ESA; updated macOS and Windows provider self-tests to cover all 22 sources

## [0.10.0] - 2026-08-23

### Added

- A local Workspace for project dashboards, Saved Searches, Smart Collections, provider health checks, and a shortcut reference
- Local-only Global Search across projects, saved media, favorites, download history, search history, Saved Searches, research references, and known local media records
- Command Palette with a compact, keyboard-first entry point for the main FootageFlow workflows
- Saved Searches that preserve query, scope, filters, relevance mode, and enabled providers without saving search-result snapshots
- Dynamic Smart Collections for recent downloads/favorites/research, downloaded media, known rights states, missing local files, and possible metadata duplicates
- Manual, lightweight Provider Health checks; no background provider polling or new network service was introduced

### Accessibility and privacy

- macOS VoiceOver and Windows Narrator labels for workspace controls, media actions, status, and keyboard-first navigation
- Keyboard shortcuts for Quick Search, Global Search, Command Palette, Projects, Favorites, Downloads, Research, and Settings, plus visible native focus handling
- Workspace search reads only FootageFlow metadata already stored locally. It does not scan arbitrary disks, send search data to a server, or index API keys, cookies, tokens, or raw logs

### Platforms and validation

- macOS Apple Silicon and Windows 11 x64 use the shared Swift Core for Workspace data, command routing, Saved Searches, and local search records
- Added persistence, legacy-decode, local-index privacy, collection, command-catalog, localization, Windows Core-host, WPF build, packaging, installer, clean-install, launch, and uninstall coverage

## [0.9.0] - 2026-08-23

### Added

- Media, Research, and All search modes; All keeps media and research in separate result groups
- Public research discovery through Wikipedia, Wikidata, The Metropolitan Museum of Art, Art Institute of Chicago, Crossref, and GDELT
- Project-scoped Research Notes with provider facts, local plain-text My Notes, tags, search/filter/sort, citation copy, original-page opening, related-media queries, and source-metadata refresh
- Research Reference and Combined Project Report export in Markdown, CSV, JSON, and HTML
- Portable `.footageflowproject` schema v2 containing sanitized research references, notes, and UTF-8 tags while retaining schema v1 import compatibility
- Research pagination, provider-level error isolation, controlled museum detail batches, public-interface request pacing, and bounded English fallback for sparse Wikipedia/Wikidata results
- **Add as Media** for a Met/AIC record only when its provider explicitly reports Public Domain and a public original-image URL

### Safety and rights

- Research results are not presented as free media: Crossref remains metadata-only, GDELT remains discovery-only, Wikipedia images require separate Commons rights verification, and museum rights are only displayed from explicit provider metadata
- Research exports and backups retain the existing secret, signed-query, private-path, HTML, and CSV formula protections

### Platforms

- macOS Apple Silicon and Windows 11 x64 share Research models, relevance ranking, citations, persistence, exports, portable-project migration, and provider behavior

### Validation

- Added research workflow tests for bounded query planning, relevance coverage, citation safety, research-reference persistence/deduplication, portable schema v2, and scoped/escaped reports
- Live public-provider smoke validated Wikipedia, Wikidata, The Met, Art Institute of Chicago, and Crossref; GDELT rate-limit responses remain isolated and non-fatal

## [0.8.0] - 2026-08-18

### Added

- Project-level attribution reports in Markdown, CSV, JSON, and offline HTML
- Concise and detailed credits for video descriptions, end credits, README files, and project notes
- Rights Audit with Public Domain, Rights Known, Attribution Required, Rights Unknown, and Original Page Unavailable summaries and filters
- Portable, versioned `.footageflowproject` backup/import across macOS and Windows without bundling large media
- Project duplicate detection for Provider IDs, normalized source/download URLs, lazy local SHA-256 hashes, and cautious metadata matches
- User-controlled duplicate decisions, including **Keep Both**, **Not a Duplicate**, and reset; removing an item from a project never deletes the media file
- PNG contact sheets with 3/4/5-column layouts, optional rights labels, shared thumbnail cache reuse, and best-effort local FFmpeg representative frames

### Improved

- Project workflow now carries existing favorites, downloads, source sidecars, search history, rights metadata, and editing/clip metadata through attribution, backup, and review tasks
- macOS and Windows use the same Swift Core export schema, rights audit, portable manifest, duplicate rules, hash cache, privacy redaction, and contact-sheet plan
- Project actions are organized under a discoverable native menu instead of adding a second project/download system

### Privacy and safety

- Exports and backups exclude API keys, credentials, cookies, private logs, raw clipboard content, sensitive URL query values, and absolute local paths by default
- CSV formula-like cells are neutralized; HTML reports escape metadata and do not require JavaScript or remote services
- Missing rights are never guessed, and FootageFlow continues to provide organization metadata rather than legal clearance

### Platforms

- macOS 15+ on Apple Silicon
- Windows 11 x64

### Validation

- Added project export, credits, rights-audit, portable-import, duplicate-decision, streaming SHA-256, large-project, localization, and cross-platform manifest fixture coverage
- macOS release build, app bundle, DMG, self-test, privacy scan, source/thumbnail/contact-sheet fallback, and installed-app smoke remain release gates
- Windows CI is the release gate for Shared Core, WPF, project workflow host tests, installer, clean installation, startup, and uninstall

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
