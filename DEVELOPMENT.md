# FootageFlow development guide

User-facing behavior is documented separately in [Provider modes](docs/PROVIDERS.md), [Link Downloader](docs/LINK_DOWNLOADER.md), [Software updates](docs/SOFTWARE_UPDATES.md), [Rights and attribution](docs/RIGHTS_AND_ATTRIBUTION.md), [Project workflow](docs/PROJECT_WORKFLOW.md), and [Troubleshooting](docs/TROUBLESHOOTING.md). Planned work belongs in [ROADMAP.md](ROADMAP.md) and public Roadmap Issues rather than being described as completed behavior here.

## Toolchain

- Swift 6 / Swift Package Manager
- SwiftUI application shell for macOS 15+
- WPF / .NET 10 application shell for Windows 11 x64
- Foundation, URLSession, Codable, async/await
- AppKit and AVKit only inside macOS integration points
- Security.framework-backed credential store on macOS and Windows Credential Manager on Windows
- Apple Translation where available, with a rule-based fallback
- Checksum-pinned yt-dlp plus redistributable GPL FFmpeg/FFprobe tooling are bundled for best-effort media analysis, clip extraction, merging, audio extraction, and editing-compatible output

The latest stable FootageFlow release targets Apple Silicon macOS 15+ and Windows 11 x64. SwiftUI, AppKit, AVKit, Apple Translation, and Security.framework remain macOS-only. The Windows WPF layer calls a local Swift Core Host over JSON stdin/stdout so all 17 search providers, ten-language query planning, pagination continuations, normalized models, rights rules, local relevance ranking, clip/output metadata, attribution, sidecars, update-version logic, portable project manifests, duplicate detection, contact-sheet plans, and the Codable project database remain single-source Swift implementations. Credentials never appear in command-line arguments.

## Multilingual search

`MultilingualQueryEngine` is the only source of the ten-language query plan. It detects the input language, maps the original query to local concept groups, creates one complete compound query for every supported UI language, and optionally adds at most two visual queries in the input language and English. The plan is capped at 14 records. Each `SearchKeyword` carries an optional language, origin, and priority so data written before v0.7.2 still decodes without migration.

macOS consumes the plan in-process. Windows requests it from the Swift Core Host's `keywords` action; the WPF layer does not duplicate the language dictionary. Apple Translation may add a macOS retrieval hint for an unknown phrase, but supporting queries never create mandatory relevance groups.

Searches use a global 12-request gate. Official/public APIs run at most two query requests per Provider; direct and yt-dlp searches run one. A 429, temporary block, invalid key, or missing key stops that Provider's remaining language wave without affecting other Providers. Results preserve matched-query language metadata, pass concept coverage first, and only then receive a small language preference in input-language, interface-language, English, other order.

## Source layout

- `Models/`: `MediaAsset`, `RightsInfo`, advanced filters, provider IDs, download availability, and the five-state license model.
- `Providers/`: independent implementations of the `MediaProvider` protocol.
- `Networking/`: validated HTTPS requests, readable error mapping, cancellation, bounded retries, and rate-limit handling.
- `Persistence/`: projects, script segments, favorites, history, and download metadata in an atomic Codable database.
- `Services/`: downloads, cache, localization, logging, credential storage, settings, preview, source sidecars, and shared project-workflow exports/audits/backups/deduplication.
- `Platform/`: replaceable system paths, file/folder opening, file reveal, and directory selection.
- `ViewModels/`: provider orchestration, progressive results, deduplication, filtering, and sorting.
- `Views/`: macOS SwiftUI presentation only.
- `Utilities/`: keyword rules, attribution formatting, batch selection, file naming, URL safety, acceptance tests, and offline self-tests.
- `Tests/`: XCTest cases and fixed provider fixtures.
- `Windows/FootageFlow.Windows/`: WPF views plus Windows-only adapters for Credential Manager, dialogs, folder reveal, MediaElement preview, direct downloads, and yt-dlp process hosting.

Business logic must not import AppKit, SwiftUI, AVKit, Security, or Translation. New platform-specific behavior belongs behind a protocol in `Platform/` or in a clearly named platform implementation.

## Provider contract

`MediaProvider` exposes provider metadata, first-page search, provider-owned continuation search, connection testing, detail lookup, and download resolution. `ProviderContinuation` can carry a page, offset, token, cursor, or next URL without forcing providers to share a network parameter. `ProviderInfo` includes explicit pagination capability alongside search, preview, metadata, license, download, media type, and access methods. Every provider maps its response into `MediaAsset`; unknown fields remain `nil`, and an absent license is always `UNKNOWN`.

`ProviderFactory` makes the automatic per-provider decision. A non-empty Pexels or Pixabay key selects the official API; an empty key selects a direct-search provider. An API failure does not silently downgrade. The user may explicitly try direct search after a rate-limit error. YouTube similarly uses Data API search when configured and the local yt-dlp adapter when not configured. NASA and Library of Congress use public official APIs without a key. National Archives and Europeana use their official APIs only with a user key; without one, `LimitedDiscoveryProvider` returns an official search URL and never scrapes HTML. Provider searches remain independent tasks, so a timeout or block never discards successful results from other sources.

Current official interfaces:

- Pexels: `GET /v1/videos/search` and `GET /v1/search`, with the API key in the `Authorization` header.
- Pixabay: `GET /api/videos/` and `GET /api/`; Pixabay search responses are cached for 24 hours.
- Wikimedia Commons: MediaWiki Action API using `generator=search`, `imageinfo`, and `extmetadata`.
- Internet Archive: Advanced Search plus `/metadata/{identifier}` for item files and rights fields.
- YouTube Data API v3: `search.list`, `part=snippet`, `type=video`; yt-dlp is an external-tool adapter for best-effort public search and downloading. It runs with `--ignore-config`, never imports browser cookies, uses bounded retries, and maps rate limits, unavailable videos, regional restrictions, and login-gated content into user-facing provider errors.
- NASA Image and Video Library: `GET https://images-api.nasa.gov/search` plus the official per-item asset manifest. Video, image, audio, and year filters are sent to the service. HTTP asset links are normalized to HTTPS. NASA ownership alone never sets Public Domain.
- Library of Congress: official `loc.gov` JSON collection search (`film-and-videos`, `photos`, or `audio-recordings`) and resource fields. Requests are spaced three seconds apart to remain within the published 20 JSON requests/minute limit. `download_restricted` resources never receive a download action.
- National Archives: `GET https://catalog.archives.gov/api/v2/records/search` with the user's key in `x-api-key`. No key means limited official-search discovery. Normalized NARA search results bypass `SearchCache` because the current Catalog API documentation says API-returned content must not be cached or stored. Persisted user actions still retain the minimum selected/download attribution metadata the user asked FootageFlow to keep.
- Europeana: Search API v2 with the user's key in `X-Api-Key`. No key means limited official-search discovery. Only video, image, and explicitly requested audio enter the media workflow; Documents/3D are not mapped.
- PeerTube/SepiaSearch: public `/api/v1/search/videos` with offset pagination. Results are discovery-only unless explicit reusable media and rights become available through a future detail adapter.
- Videvo, Videezy, and Mixkit: limited discovery that opens official search pages. FootageFlow does not scrape restricted pages or infer item licenses.
- Coverr: official `/videos` API with a user-provided key, zero-based page pagination, signed preview/download URLs, and conservative attribution-required rights output. No key opens official search.
- Vimeo: official `/videos` discovery with a user token and page pagination. Public discovery remains non-downloadable even when a metadata privacy flag mentions downloads; reuse rights come only from explicit license metadata.
- Openverse: public anonymous `/v1/images/` and `/v1/audio/` search with independent pagination. Images and audio preserve item URLs, direct media, creator, license URL, attribution, dimensions/duration, and source metadata. Audio duration is normalized from API milliseconds. Rights are never inferred beyond each response.
- Dailymotion: current public `/videos` discovery fields with page pagination. Results provide title, owner/creator, duration, thumbnail, and original page, remain discovery-only, and keep rights unknown unless explicit rights metadata becomes available. Link Downloader may separately attempt a public Dailymotion URL through yt-dlp.
- Pexels/Pixabay direct mode reads only ordinary public result pages with a short timeout and no authentication, cookie import, CAPTCHA handling, Cloudflare bypass, or anti-bot parameter fabrication. A 403 is treated as a temporary block and suggests the optional official API mode.

`ProviderRequestLimiter` centralizes minimum request spacing. `HTTPClient` uses an ephemeral session, bounded exponential retry for 429/5xx responses, readable errors, no cookies, and no URL cache. API keys are sent only in provider-required headers. Search state retains one continuation per provider/query pair, appends de-duplicated results, restores failed continuations for retry, and rejects late pages from an old query.

## Two-stage search relevance

Provider search is the high-recall first stage. `SearchRelevanceEngine` is the shared deterministic second stage used by the macOS view model, script search, and Windows Core Host. It derives concept groups from the original query plus a visible translation when necessary, then scores title, tags/keywords, category, description, creator/channel, bounded Provider relevance, and the matched retrieval query. A matched retrieval query is a small signal only and cannot prove that an item covers a concept.

Balanced is the persisted default and requires all groups for two-concept queries or at least two-thirds for larger queries. Precise requires every group in high-weight metadata. Broad requires at least one concept and exposes weaker candidates. PeerTube/SepiaSearch, Library of Congress, Internet Archive, and YouTube receive a modest threshold adjustment based on their broad full-text behavior. The rules are semantic categories and language aliases, not per-query result patches.

The unfiltered candidate pool is retained for mode changes and pagination. Every incoming Provider batch is de-duplicated and re-ranked, so progressive delivery remains intact. Pexels videos are the only explicit query-trust fallback because the official API supplies no per-video title, tags, or description; the synthetic UI title itself is excluded from scoring. See `docs/SEARCH_RELEVANCE_AUDIT.md` for root causes, the fixed evaluation set, and live measurements.

## Thumbnail pipeline

Providers return ordered `thumbnailCandidates`; `MediaAsset.effectiveThumbnailCandidates` performs backward-compatible recovery from the old primary URL and metadata fields. `ThumbnailResolver` is the only shared URL normalization point. It accepts absolute, protocol-relative, and relative values, upgrades HTTP candidates to HTTPS, rejects credentials/malformed URLs, removes duplicates, and resolves PeerTube relative paths against the result's own instance rather than SepiaSearch.

The macOS `ThumbnailPipeline` and Windows `ThumbnailLoaderService` use ephemeral/cookieless requests, a FootageFlow User-Agent, bounded timeout, redirect handling, cancellation, HTTP and Content-Type checks, image signature detection, candidate fallback, six-hour successful memory caching, and a 45-second failed-response cache. HTML error pages, empty responses, 403/404/429 responses, and decode failures never enter the successful cache. macOS decodes through `NSImage`; Windows first asks for JPEG/PNG, then uses WIC for JPEG/PNG/GIF and installed WebP/AVIF codecs, falling through to the next candidate if decoding is unavailable. No global ATS exception or insecure HTTP fallback is enabled.

Run `FootageFlow --thumbnail-smoke <query>` to collect a sanitized live report. It never prints query strings from signed thumbnail URLs or credentials. See `docs/THUMBNAIL_PIPELINE_AUDIT.md` for the v0.5.0 diagnosis and evidence.

## Link Downloader

`YTDLPService.analyze` is the shared metadata and format normalizer. It always passes `--ignore-config`, never imports browser cookies, rejects embedded URL credentials and sensitive query parameters, blocks loopback/local/private-network addresses, excludes DRM-marked formats, and maps unsupported, unavailable, login-gated, region-restricted, and rate-limited failures. Selected quality, subtitle language, source name, output preset, and validated clip range are stored as non-secret `MediaAsset.originalMetadata` fields. Source sidecars redact sensitive URL query values before writing either text or JSON metadata.

The macOS `DownloadManager` and Windows `DownloadQueueService` read those fields and call their existing yt-dlp adapters. Link tasks therefore use the normal concurrency, cancellation, retry, progress, speed, sidecar, download-history, and folder-reveal paths. `ClipTimeRange` accepts seconds, `MM:SS`, or `HH:MM:SS`, rejects unknown/out-of-bounds duration and sub-0.5-second ranges, and is passed through yt-dlp's documented `--download-sections` path. Output presets retain the original, extract M4A, or produce a verified MP4 with H.264 video, AAC audio when present, yuv420p, and fast-start metadata. Compatible MP4 input is stream-copied; other input is transcoded and probed before completion.

`KeywordEngine` remains local and deterministic. It keeps the original query first, detects supported Chinese, Spanish, Portuguese, Japanese, Korean, German, French, Russian, and English concepts, produces at most five visible editable queries, and applies a provider-specific request budget. Compound rules generate compound searches rather than standalone broad entities. Disabled expansion uses only the original query. No cloud LLM or paid AI API is involved.

Clipboard link detection is platform-specific only at the pasteboard boundary. The shared parser accepts public media URLs, rejects embedded credentials and local/private-network targets, de-duplicates the current session, honors ignore/cooldown, and never logs or uploads clipboard content. The preference defaults to off and polling occurs only while the app window is active.

## Update checking

`AppUpdateService` is a platform-neutral actor that reads only the latest non-draft, non-prerelease item from GitHub's public Releases API. It validates semantic versions, converts bounded Markdown Release Notes into inert plain text, accepts only this repository's HTTPS release links, and maps offline, timeout, rate-limit, server, and response failures into stable error codes. There is no persisted skip or reminder cooldown. Not Now is held only in the current platform session.

macOS uses `AppUpdateController` and a SwiftUI sheet; Windows sends `checkUpdate` to the same Swift Core Host and presents the result in a WPF dialog. Both shells check asynchronously once per launch after the main window loads, show at most one automatic dialog per session, keep startup failures unobtrusive, offer a manual Settings action, and only open the official release page after **View Update**. A complete restart creates a fresh session and therefore reminds an outdated installation again. Neither shell contains an installer or automatic-download path.

## Rights, filtering, and batch behavior

`RightsInfo` keeps the provider statement, URI, metadata source, known/public-domain/open-license/attribution facts, and optional commercial-use knowledge. Legacy v0.2.0 `MediaAsset` JSON without these fields remains decodable. Unknown data stays unknown; provider identity and download success never imply reuse rights.

`AdvancedSearchFilter` composes source, media type, year, duration, resolution, rights, and `Downloadable Only`. The last option matches only `.direct`; YouTube and other conditional actions are deliberately excluded. A missing year, duration, resolution, or rights value does not pass a filter that requires that value.

`AssetSelection` stores stable `provider:id` values and intersects the set with each new result collection, so a new search cannot act on stale cards. Both shells feed selected downloads into their existing maximum-three queues. Per-task failure does not stop the batch, and the Download Manager exposes Retry Failed.

`AttributionFormatter` is shared by macOS, the Windows Core Host, result-card copy actions, batch source copying, and source sidecars. It omits missing optional fields and uses the localized unknown-rights warning rather than inventing a license.

## Project workflow and portability

`ProjectAssetInventory` is a project-scoped view over the existing favorite and download records rather than a new asset database. `AttributionExporter` creates Markdown/CSV/JSON/HTML reports and concise/detailed credits from selected metadata. Absolute local paths are omitted by default, sensitive URL values and common credential/path patterns are redacted, HTML is escaped, and CSV formula-like values are neutralized. A rights-audit acknowledgement is independent from `RightsInfo`, so a user cannot accidentally convert unknown provider data into a known license.

`PortableProjectCodec` serializes the versioned `.footageflowproject` UTF-8 JSON manifest. It includes project structure and selected metadata, but no media binaries, secure credentials, or absolute paths. Imports validate schema, project identity, asset metadata, and relative references before `PersistentStore` writes the fully constructed payload atomically. Old databases retain optional v0.8 fields and decode without migration.

`DuplicateDetectionEngine` evaluates stable Provider IDs, canonical original/download URLs, optional lazy SHA-256 hashes, then possible metadata. Hashes use chunked reads and a size/modification cache; they never leave the device. `ContactSheetPlanner` is shared; macOS and Windows render its PNG with their native frameworks, first reusing thumbnails and then optionally extracting a bounded 15%-timeline local-video frame through bundled FFmpeg.

To add a provider:

1. Add a type conforming to `MediaProvider` under `Providers/`.
2. Validate every remote URL with `URLValidator`.
3. Map only provider-supplied metadata; do not infer licenses.
4. Register its selection rules in `ProviderFactory`, script batch search, Settings, and localization resources.
5. Declare its real capabilities and access methods; discovery-only providers do not need download support.
6. Add fixed fixtures, XCTest parsing coverage, and an offline self-test where practical.
7. Document quota, attribution, caching, and download restrictions.

## Persistence and privacy

The Codable database stores metadata and local file paths, never video/image binaries or API keys. Writes are atomic. `PersistentStore` is shared by both platforms. macOS accesses API keys through Keychain; Windows uses generic credentials in Windows Credential Manager through `CredWriteW`, `CredReadW`, and `CredDeleteW`. Windows' ordinary `settings.json` contains language, enabled sources, and download path only.

Downloads are restricted to the configured root for app-initiated deletion. A successful media download is not recorded until matching `.source.txt` and `.source.json` files are written.

## Localization

English is the fixed first-launch default. `en.lproj` is the fallback for missing translations. v0.8.0 ships `en`, `zh-Hans`, `zh-Hant`, `es`, `pt-BR`, `ja`, `ko`, `de`, `fr`, and `ru`. SwiftPM may normalize language-directory casing in the built resource bundle, so locale lookup also checks normalized identifiers.

Run `scripts/check_localizations.sh` after changing UI copy. `localization.fallbackProbe` intentionally exists only in English to exercise fallback behavior.

## Build and test

```bash
scripts/lint.sh
scripts/secret_scan.sh
swift build -c release
swift test
scripts/build_app.sh
scripts/verify_app.sh
dist/FootageFlow.app/Contents/MacOS/FootageFlow --self-test
dist/FootageFlow.app/Contents/MacOS/FootageFlow --live-smoke
dist/FootageFlow.app/Contents/MacOS/FootageFlow --creator-workflow-smoke /tmp/FootageFlowCreatorSmoke
dist/FootageFlow.app/Contents/MacOS/FootageFlow --update-smoke
dist/FootageFlow.app/Contents/MacOS/FootageFlow --relevance-smoke "广州美食"
```

`--self-test` is fully offline. `--live-smoke` searches public providers and verifies no-key/limited modes. `--creator-workflow-smoke` uses public media to analyze YouTube, Dailymotion, and a direct link, then validates a 10-second H.264/AAC/yuv420p fast-start MP4 and both source sidecars. `--update-smoke` performs an end-to-end read of the latest official GitHub Release without changing local state. `--relevance-smoke` measures Provider-order and local-ranked Top-20 concept coverage across public sources. `--acceptance-test <directory>` additionally downloads a small Public Domain fixture, creates both sidecars, checks persistence, and simulates a friendly network error. Fixed JSON fixtures cover all providers, including Openverse, Dailymotion, and GitHub release metadata. Tests cover update version comparison/reminders/link validation, clip validation, output metadata/history/sidecars, concept relevance, search modes, smart expansion and query budgets, clipboard safety, continuations, rights, localization, and project/download behavior. The Windows runner also executes Credential Manager, the shared `rankAssets` Core Host action, creator-workflow media validation, cancel/retry, packaging, clean-install, GUI-startup, uninstall, and bundled-tool tests.

The package uses the official `swift-testing` dependency so the full platform-neutral test suite also runs with Command Line Tools. GitHub Actions additionally runs `swift test` with full Xcode on macOS and the official Swift toolchain on Windows.

## Packaging

`scripts/build_app.sh` builds a Release executable; bundles checksum-pinned yt-dlp; builds static GPL FFmpeg 8.0.3 with pinned x264, Apple SecureTransport, and no `nonfree` component; copies all applicable license texts; creates the `.app`; and performs Ad Hoc signing. The FFmpeg configuration uses a neutral build prefix and the packaging scan rejects private developer paths. `scripts/binary_privacy_scan.sh` scans the app executable and bundled tools for credential-like strings. `scripts/build_dmg.sh` creates the drag-to-Applications DMG and SHA-256 checksum. No Developer ID certificate or notarization is claimed for v0.8.0.

## Windows architecture

Windows development remains in this repository and shares the same release history as macOS. `Package.swift` excludes macOS presentation files when it is evaluated on Windows, then builds the same Provider and Foundation core as `FootageFlowCore.exe`. The WPF client starts one short-lived Core Host request per provider, allowing results to appear progressively and cancellation to terminate only that provider process. A failed provider returns a normalized batch and cannot fail the aggregate search.

The platform split is deliberate:

- Shared Swift: all 17 search provider implementations and modes, pagination, networking/rate policy, `MediaAsset`, `RightsInfo`, capabilities, filters, concept-aware relevance ranking, attribution, feedback URL building, smart keyword rules, clip/output models, clipboard URL safety, update release parsing/version/reminder policy, deduplication, filename suggestions, source sidecars, and project/favorite/history/download metadata.
- macOS: SwiftUI/AppKit/AVKit, Keychain, Apple Translation, Finder integration, and URLSession download presentation.
- Windows: WPF/MediaElement, Credential Manager, Explorer/file dialogs, a bounded `HttpClient` download queue, and yt-dlp process execution. yt-dlp JSON is mapped back into `MediaAsset` by the shared Swift mapper.

The Windows CI job builds the shared Swift core, runs Swift and Windows acceptance tests, publishes a self-contained WPF runtime, bundles pinned yt-dlp and the required Swift runtime DLLs, builds the Inno Setup installer, performs a clean install, checks the installed Core Host and native WPF startup separately, uninstalls, runs real no-key Provider smoke tests, and publishes checksummed artifacts. See `docs/WINDOWS_ARCHITECTURE.md` for the audit, packaging boundary, validation evidence, and migration risks.
