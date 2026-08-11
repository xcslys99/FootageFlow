# FootageFlow development guide

## Toolchain

- Swift 6 / Swift Package Manager
- SwiftUI application shell for macOS 15+
- WPF / .NET 10 application shell for Windows 11 x64
- Foundation, URLSession, Codable, async/await
- AppKit and AVKit only inside macOS integration points
- Security.framework-backed credential store on macOS and Windows Credential Manager on Windows
- Apple Translation where available, with a rule-based fallback
- A checksum-pinned yt-dlp macOS executable is bundled for local, best-effort YouTube interoperability; no FFmpeg binary is bundled

FootageFlow v0.5.0 targets Apple Silicon macOS 15+ and Windows 11 x64. SwiftUI, AppKit, AVKit, Apple Translation, and Security.framework remain macOS-only. The Windows WPF layer calls a local Swift Core Host over JSON stdin/stdout so all 15 search providers, pagination continuations, normalized models, rights rules, filters, attribution, feedback URLs, sidecars, and the Codable project database remain single-source Swift implementations. Credentials never appear in command-line arguments.

## Source layout

- `Models/`: `MediaAsset`, `RightsInfo`, advanced filters, provider IDs, download availability, and the five-state license model.
- `Providers/`: independent implementations of the `MediaProvider` protocol.
- `Networking/`: validated HTTPS requests, readable error mapping, cancellation, bounded retries, and rate-limit handling.
- `Persistence/`: projects, script segments, favorites, history, and download metadata in an atomic Codable database.
- `Services/`: downloads, cache, localization, logging, credential storage, settings, preview, and source sidecars.
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
- Pexels/Pixabay direct mode reads only ordinary public result pages with a short timeout and no authentication, cookie import, CAPTCHA handling, Cloudflare bypass, or anti-bot parameter fabrication. A 403 is treated as a temporary block and suggests the optional official API mode.

`ProviderRequestLimiter` centralizes minimum request spacing. `HTTPClient` uses an ephemeral session, bounded exponential retry for 429/5xx responses, readable errors, no cookies, and no URL cache. API keys are sent only in provider-required headers. Search state retains one continuation per provider/query pair, appends de-duplicated results, restores failed continuations for retry, and rejects late pages from an old query.

## Thumbnail pipeline

Providers return ordered `thumbnailCandidates`; `MediaAsset.effectiveThumbnailCandidates` performs backward-compatible recovery from the old primary URL and metadata fields. `ThumbnailResolver` is the only shared URL normalization point. It accepts absolute, protocol-relative, and relative values, upgrades HTTP candidates to HTTPS, rejects credentials/malformed URLs, removes duplicates, and resolves PeerTube relative paths against the result's own instance rather than SepiaSearch.

The macOS `ThumbnailPipeline` and Windows `ThumbnailLoaderService` use ephemeral/cookieless requests, a FootageFlow User-Agent, bounded timeout, redirect handling, cancellation, HTTP and Content-Type checks, image signature detection, candidate fallback, six-hour successful memory caching, and a 45-second failed-response cache. HTML error pages, empty responses, 403/404/429 responses, and decode failures never enter the successful cache. macOS decodes through `NSImage`; Windows first asks for JPEG/PNG, then uses WIC for JPEG/PNG/GIF and installed WebP/AVIF codecs, falling through to the next candidate if decoding is unavailable. No global ATS exception or insecure HTTP fallback is enabled.

Run `FootageFlow --thumbnail-smoke <query>` to collect a sanitized live report. It never prints query strings from signed thumbnail URLs or credentials. See `docs/THUMBNAIL_PIPELINE_AUDIT.md` for the v0.5.0 diagnosis and evidence.

## Link Downloader

`YTDLPService.analyze` is the shared metadata and format normalizer. It always passes `--ignore-config`, never imports browser cookies, rejects embedded URL credentials and sensitive query parameters, blocks loopback/local/private-network addresses, excludes DRM-marked formats, and maps unsupported, unavailable, login-gated, region-restricted, and rate-limited failures. Selected quality, subtitle language, and source name are stored as non-secret `MediaAsset.originalMetadata` fields. Source sidecars redact sensitive URL query values before writing either text or JSON metadata.

The macOS `DownloadManager` and Windows `DownloadQueueService` read those fields and call their existing yt-dlp adapters. Link tasks therefore use the normal concurrency, cancellation, retry, progress, speed, sidecar, download-history, and folder-reveal paths. Audio Only selects an available audio stream without FFmpeg conversion. Separate-stream merging and subtitle embedding are not promised because FootageFlow does not bundle FFmpeg.

## Rights, filtering, and batch behavior

`RightsInfo` keeps the provider statement, URI, metadata source, known/public-domain/open-license/attribution facts, and optional commercial-use knowledge. Legacy v0.2.0 `MediaAsset` JSON without these fields remains decodable. Unknown data stays unknown; provider identity and download success never imply reuse rights.

`AdvancedSearchFilter` composes source, media type, year, duration, resolution, rights, and `Downloadable Only`. The last option matches only `.direct`; YouTube and other conditional actions are deliberately excluded. A missing year, duration, resolution, or rights value does not pass a filter that requires that value.

`AssetSelection` stores stable `provider:id` values and intersects the set with each new result collection, so a new search cannot act on stale cards. Both shells feed selected downloads into their existing maximum-three queues. Per-task failure does not stop the batch, and the Download Manager exposes Retry Failed.

`AttributionFormatter` is shared by macOS, the Windows Core Host, result-card copy actions, batch source copying, and source sidecars. It omits missing optional fields and uses the localized unknown-rights warning rather than inventing a license.

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

English is the fixed first-launch default. `en.lproj` is the fallback for missing translations. v0.5.0 ships `en`, `zh-Hans`, `zh-Hant`, `es`, `pt-BR`, `ja`, `ko`, `de`, `fr`, and `ru`. SwiftPM may normalize language-directory casing in the built resource bundle, so locale lookup also checks normalized identifiers.

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
```

`--self-test` is fully offline. `--live-smoke` searches public providers and verifies no-key/limited modes. `--acceptance-test <directory>` additionally downloads a small Public Domain fixture, creates both sidecars, checks persistence, and simulates a friendly network error. Fixed JSON fixtures cover existing and v0.5.0 providers plus link analysis. Tests cover continuations, discovery/download boundaries, format selection, safe feedback URLs, localization, persistence, sidecars, and project/download behavior. The Windows runner also executes Credential Manager, Core Host, cancel/retry, packaging, clean-install, GUI-startup, and uninstall tests.

This Mac currently has Command Line Tools rather than full Xcode. Release builds and offline self-tests work locally, while `swift test` reports that XCTest is unavailable. GitHub Actions runs XCTest on a full Xcode image.

## Packaging

`scripts/build_app.sh` builds a Release executable, downloads the fixed yt-dlp release only when it is not already cached, verifies its SHA-256, creates the `.app`, copies localized resources without embedding a developer path, generates the original FootageFlow icon, and performs Ad Hoc signing. `scripts/binary_privacy_scan.sh` scans the app executable and bundled tool for credential-like strings. `scripts/build_dmg.sh` creates the drag-to-Applications DMG and SHA-256 checksum. No Developer ID certificate or notarization is claimed for v0.5.0.

## Windows architecture

Windows development remains in this repository and shares the same release history as macOS. `Package.swift` excludes macOS presentation files when it is evaluated on Windows, then builds the same Provider and Foundation core as `FootageFlowCore.exe`. The WPF client starts one short-lived Core Host request per provider, allowing results to appear progressively and cancellation to terminate only that provider process. A failed provider returns a normalized batch and cannot fail the aggregate search.

The platform split is deliberate:

- Shared Swift: all 15 search provider implementations and modes, pagination, networking/rate policy, `MediaAsset`, `RightsInfo`, capabilities, filters, attribution, feedback URL building, keyword rules, deduplication, filename suggestions, source sidecars, and project/favorite/history/download metadata.
- macOS: SwiftUI/AppKit/AVKit, Keychain, Apple Translation, Finder integration, and URLSession download presentation.
- Windows: WPF/MediaElement, Credential Manager, Explorer/file dialogs, a bounded `HttpClient` download queue, and yt-dlp process execution. yt-dlp JSON is mapped back into `MediaAsset` by the shared Swift mapper.

The Windows CI job builds the shared Swift core, runs Swift and Windows acceptance tests, publishes a self-contained WPF runtime, bundles pinned yt-dlp and the required Swift runtime DLLs, builds the Inno Setup installer, performs a clean install, checks the installed Core Host and native WPF startup separately, uninstalls, runs real no-key Provider smoke tests, and publishes checksummed artifacts. See `docs/WINDOWS_ARCHITECTURE.md` for the audit, packaging boundary, validation evidence, and migration risks.
