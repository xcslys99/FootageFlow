# FootageFlow development guide

## Toolchain

- Swift 6 / Swift Package Manager
- SwiftUI application shell for macOS 15+
- Foundation, URLSession, Codable, async/await
- AppKit and AVKit only inside macOS integration points
- Security.framework-backed credential store on macOS
- Apple Translation where available, with a rule-based fallback
- No third-party runtime dependencies

The current release target is Apple Silicon macOS. Swift itself supports Windows, but SwiftUI, AppKit, AVKit, Apple Translation, and Security.framework do not. The future Windows app will share the core package and provide a Windows-specific UI and platform adapters.

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

Business logic must not import AppKit, SwiftUI, AVKit, Security, or Translation. New platform-specific behavior belongs behind a protocol in `Platform/` or in a clearly named platform implementation.

## Provider contract

`MediaProvider` exposes provider metadata, search, connection testing, detail lookup, and download resolution. Every provider maps its response into `MediaAsset`; unknown fields remain `nil`, and an absent license is always `UNKNOWN`.

Current official interfaces:

- Pexels: `GET /v1/videos/search` and `GET /v1/search`, with the API key in the `Authorization` header.
- Pixabay: `GET /api/videos/` and `GET /api/`; Pixabay search responses are cached for 24 hours.
- Wikimedia Commons: MediaWiki Action API using `generator=search`, `imageinfo`, and `extmetadata`.
- Internet Archive: Advanced Search plus `/metadata/{identifier}` for item files and rights fields.
- YouTube Data API v3: `search.list`, `part=snippet`, `type=video`. YouTube is source discovery only and is never marked downloadable.

To add a provider:

1. Add a type conforming to `MediaProvider` under `Providers/`.
2. Validate every remote URL with `URLValidator`.
3. Map only provider-supplied metadata; do not infer licenses.
4. Register the provider in `SearchViewModel`, script batch search, Settings, and localization resources.
5. Add fixed JSON fixtures, XCTest parsing coverage, and an offline self-test where practical.
6. Document quota, attribution, caching, and download restrictions.

## Persistence and privacy

The Codable database stores metadata and local file paths, never video/image binaries or API keys. Writes are atomic. API keys are accessed through `CredentialStoring`; the macOS implementation uses Keychain and the future Windows implementation must use Windows Credential Manager or an equivalent secure OS facility.

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

`--self-test` is fully offline. `--live-smoke` searches Wikimedia Commons and Internet Archive and verifies missing-key behavior. `--acceptance-test <directory>` additionally downloads a small Public Domain fixture, creates both sidecars, checks persistence, and simulates a friendly network error.

This Mac currently has Command Line Tools rather than full Xcode. Release builds and offline self-tests work locally, while `swift test` reports that XCTest is unavailable. GitHub Actions runs XCTest on a full Xcode image.

## Packaging

`scripts/build_app.sh` builds a Release executable, creates the `.app`, copies the SwiftPM resource bundle, generates the original FootageFlow icon, and performs Ad Hoc signing. `scripts/build_dmg.sh` creates the drag-to-Applications DMG and SHA-256 checksum. No Developer ID certificate or notarization is claimed for v0.1.0.

## Windows direction

The Windows release is intentionally deferred until macOS v0.1.0 stabilizes. It should live in this repository and share models, provider parsers, search orchestration, fixtures, license rules, sidecar schema, and most download logic. Windows-specific work includes UI, credential storage, file dialogs, external opening/reveal, media preview, translation fallback, installer generation, and system paths.
