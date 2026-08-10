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

FootageFlow v0.2.0 targets Apple Silicon macOS 15+ and Windows 11 x64. SwiftUI, AppKit, AVKit, Apple Translation, and Security.framework remain macOS-only. The Windows WPF layer calls a local Swift Core Host over JSON stdin/stdout so provider behavior, normalized models, license rules, keyword rules, sidecars, and the Codable project database remain single-source Swift implementations. Credentials never appear in command-line arguments.

## Source layout

- `Models/`: `MediaAsset`, filters, provider IDs, and the five-state license model.
- `Providers/`: independent implementations of the `MediaProvider` protocol.
- `Networking/`: validated HTTPS requests, readable error mapping, cancellation, bounded retries, and rate-limit handling.
- `Persistence/`: projects, script segments, favorites, history, and download metadata in an atomic Codable database.
- `Services/`: downloads, cache, localization, logging, credential storage, settings, preview, and source sidecars.
- `Platform/`: replaceable system paths, file/folder opening, file reveal, and directory selection.
- `ViewModels/`: provider orchestration, progressive results, deduplication, filtering, and sorting.
- `Views/`: macOS SwiftUI presentation only.
- `Utilities/`: keyword rules, file naming, URL safety, acceptance tests, and offline self-tests.
- `Tests/`: XCTest cases and fixed provider fixtures.
- `Windows/FootageFlow.Windows/`: WPF views plus Windows-only adapters for Credential Manager, dialogs, folder reveal, MediaElement preview, direct downloads, and yt-dlp process hosting.

Business logic must not import AppKit, SwiftUI, AVKit, Security, or Translation. New platform-specific behavior belongs behind a protocol in `Platform/` or in a clearly named platform implementation.

## Provider contract

`MediaProvider` exposes provider metadata, search, connection testing, detail lookup, and download resolution. `ProviderInfo` contains a `ProviderMode` and explicit `ProviderCapabilities` for search, preview, metadata, license, download, media type, and access methods. Capabilities can be supported, unavailable, or best-effort. Every provider maps its response into `MediaAsset`; unknown fields remain `nil`, and an absent license is always `UNKNOWN`.

`ProviderFactory` makes the automatic per-provider decision. A non-empty Pexels or Pixabay key selects the official API; an empty key selects a direct-search provider. An API failure does not silently downgrade. The user may explicitly try direct search after a rate-limit error. YouTube similarly uses Data API search when configured and the local yt-dlp adapter when not configured. Provider searches remain independent tasks, so a timeout or block never discards successful results from other sources.

Current official interfaces:

- Pexels: `GET /v1/videos/search` and `GET /v1/search`, with the API key in the `Authorization` header.
- Pixabay: `GET /api/videos/` and `GET /api/`; Pixabay search responses are cached for 24 hours.
- Wikimedia Commons: MediaWiki Action API using `generator=search`, `imageinfo`, and `extmetadata`.
- Internet Archive: Advanced Search plus `/metadata/{identifier}` for item files and rights fields.
- YouTube Data API v3: `search.list`, `part=snippet`, `type=video`; yt-dlp is an external-tool adapter for best-effort public search and downloading. It runs with `--ignore-config`, never imports browser cookies, uses bounded retries, and maps rate limits, unavailable videos, regional restrictions, and login-gated content into user-facing provider errors.
- Pexels/Pixabay direct mode reads only ordinary public result pages with a short timeout and no authentication, cookie import, CAPTCHA handling, Cloudflare bypass, or anti-bot parameter fabrication. A 403 is treated as a temporary block and suggests the optional official API mode.

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

English is the fixed first-launch default. `en.lproj` is the fallback for missing translations. Simplified Chinese is in `zh-Hans.lproj`; SwiftPM may normalize that directory to lowercase in the built resource bundle.

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

`--self-test` is fully offline. `--live-smoke` searches Wikimedia Commons and Internet Archive and verifies no-key direct mode, including graceful direct-search blocking. `--acceptance-test <directory>` additionally downloads a small Public Domain fixture, creates both sidecars, checks persistence, and simulates a friendly network error.

This Mac currently has Command Line Tools rather than full Xcode. Release builds and offline self-tests work locally, while `swift test` reports that XCTest is unavailable. GitHub Actions runs XCTest on a full Xcode image.

## Packaging

`scripts/build_app.sh` builds a Release executable, downloads the fixed yt-dlp release only when it is not already cached, verifies its SHA-256, creates the `.app`, copies localized resources without embedding a developer path, generates the original FootageFlow icon, and performs Ad Hoc signing. `scripts/binary_privacy_scan.sh` scans the app executable and bundled tool for credential-like strings. `scripts/build_dmg.sh` creates the drag-to-Applications DMG and SHA-256 checksum. No Developer ID certificate or notarization is claimed for v0.2.0.

## Windows architecture

Windows development remains in this repository and shares the same release history as macOS. `Package.swift` excludes macOS presentation files when it is evaluated on Windows, then builds the same Provider and Foundation core as `FootageFlowCore.exe`. The WPF client starts one short-lived Core Host request per provider, allowing results to appear progressively and cancellation to terminate only that provider process. A failed provider returns a normalized batch and cannot fail the aggregate search.

The platform split is deliberate:

- Shared Swift: provider implementations and modes, networking, `MediaAsset`, capabilities, license state, keyword rules, deduplication, filename suggestions, source sidecars, and project/favorite/history/download metadata.
- macOS: SwiftUI/AppKit/AVKit, Keychain, Apple Translation, Finder integration, and URLSession download presentation.
- Windows: WPF/MediaElement, Credential Manager, Explorer/file dialogs, a bounded `HttpClient` download queue, and yt-dlp process execution. yt-dlp JSON is mapped back into `MediaAsset` by the shared Swift mapper.

The Windows CI job builds the shared Swift core, runs Swift and Windows acceptance tests, publishes a self-contained WPF runtime, bundles pinned yt-dlp and the required Swift runtime DLLs, builds the Inno Setup installer, performs a clean install, checks the installed Core Host and native WPF startup separately, uninstalls, runs real no-key Provider smoke tests, and publishes checksummed artifacts. See `docs/WINDOWS_ARCHITECTURE.md` for the audit, packaging boundary, validation evidence, and migration risks.
