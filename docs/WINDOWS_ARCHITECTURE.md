# Windows architecture audit

Status: Windows 11 x64 is supported from FootageFlow v0.2.0. The v0.6.0 candidate keeps the same shared-core boundary and adds clip downloads, smart search expansion, creator output presets, optional local clipboard detection, Openverse, and Dailymotion to both desktop interfaces. Windows-native installation and runtime checks are performed on a clean Windows GitHub Actions runner before release.

## Current shared code

All 17 search Provider implementations, API/direct-mode selection, pagination continuations, `HTTPClient`, normalized `MediaAsset`, rights mapping, Provider capabilities and errors, smart keyword rules, clip/output models, clipboard URL parsing, deduplication, filters, filename suggestions, feedback URLs, source-sidecar generation, path roots, log redaction, and Codable persistence are platform-neutral Swift. macOS and Windows therefore use one business implementation for the existing providers plus Openverse and Dailymotion.

`PersistentStore` owns project, segment, favorite, history, and download-record behavior. The macOS `DataStore` is a small Combine presentation facade over this shared repository. Windows calls the same repository through the local Core Host.

## macOS-only code

SwiftUI views, `SearchViewModel`, AppKit windows and file panels, AVKit preview, Apple Translation, Security.framework Keychain, macOS process presentation, Finder reveal, and URLSession download presentation remain macOS-only. Swift Package Manager excludes those presentation sources when building on Windows; their implementation is otherwise unchanged.

## Reuse estimate

Approximately 80% of core behavior is shared. Provider, pagination, rights, project persistence, filename, attribution, and sidecar behavior are single-source Swift. Presentation, secure storage, external-process lifecycle, preview, dialogs, and operating-system integration are intentionally implemented per platform.

## Windows UI technology

WPF on .NET 10 is used for the Windows 11 x64 interface. WPF provides a native Windows window/control model, XAML data binding, MediaElement preview, accessibility, high-DPI behavior, and self-contained deployment. Normal users do not install .NET, Swift, Python, Node.js, yt-dlp, or FFmpeg separately.

## Shared architecture

```text
WPF UI and Windows adapters
        |
        | JSON over stdin/stdout (secrets never in argv)
        v
Swift FootageFlowCore.exe
        |
        +-- ProviderFactory and 17 search providers
        +-- pagination, models, rights, filters, smart keywords, clip/output metadata, dedupe
        +-- PersistentStore, feedback URLs and source sidecars

macOS SwiftUI UI
        |
        +-- the same Swift core types and providers in-process
```

The WPF orchestrator launches Provider requests independently. Results can appear as each source completes; cancellation or timeout stops only the affected request. Each successful batch carries its Provider-owned continuation, while a failed next page keeps the already displayed results and previous retry position.

Pexels and Pixabay still use best-effort direct search without a key and only their official APIs with a configured key. National Archives, Europeana, Coverr, and Vimeo similarly select their supported key/no-key mode in `ProviderFactory`. The Windows yt-dlp adapter uses `--ignore-config`, does not import browser cookies, rejects embedded credentials/private network addresses, and maps errors to the same user-facing states as macOS.

Link Downloader uses the existing Windows `DownloadQueueService`, cancellation tokens, progress, retry, project folder, source sidecars, and download history. Full/clip scope and output presets create normal queue assets rather than a second queue. Only yt-dlp/FFmpeg process control and WPF presentation are Windows-specific; media metadata and file-source records use the same shared models.

## Windows-only responsibilities

- Windows Credential Manager for API keys.
- `%LOCALAPPDATA%\FootageFlow` settings/log/database roots and the user's Videos folder for downloads.
- Windows-invalid and reserved filename protection, long-path manifest support, and conflict-safe filenames.
- Explorer open/reveal, folder chooser, WPF MediaElement/image preview.
- Bounded direct-download queue and yt-dlp child-process cancellation.
- Self-contained .NET publish, Swift runtime DLL collection, bundled pinned yt-dlp and GPL FFmpeg/FFprobe, and Inno Setup installer.

## Migration and release risks

- Swift Foundation behavior and runtime DLL packaging differ on Windows and must be verified on the Windows runner.
- WPF cannot reuse SwiftUI/AppKit view code; only business behavior is shared.
- yt-dlp is best-effort and changes upstream. It remains checksum-pinned and never loads browser cookies or user configuration.
- An unsigned installer can trigger Microsoft Defender SmartScreen. Release notes must describe signing status honestly.
- Windows path rules, Chinese/space paths, cancellation, clean install, and uninstall require Windows-native acceptance tests.
- Provider websites can rate-limit or change independently. One source failure never fails the aggregate search.

## Expected macOS impact

The v0.6.0 work adds shared models and narrow UI entries without replacing the existing macOS stack. Every Windows change continues to run the macOS Release build, test suite, app-bundle signing check, binary privacy scan, and offline self-test.

## Version plan

- v0.1.0 remains unchanged and macOS-only.
- v0.2.0 introduced Windows 11 x64 support.
- v0.5.0 added Search Expansion, Provider pagination, Link Downloader, and Feedback & Community on both supported platforms.
- v0.6.0 is one creator-workflow release for clip downloads, smart expansion, output presets, local clipboard detection, Openverse, and Dailymotion.
- Windows 10 x64 is not declared supported because it has not completed the same validation.

## v0.6.0 release validation gate

Before publishing v0.6.0, CI must complete all of the following on a clean Windows runner:

- Shared Swift Release build, Core Host health check, and cross-platform tests.
- Native WPF Release build and Windows platform acceptance checks.
- Self-contained publish, Swift runtime collection, pinned yt-dlp/FFmpeg checksum verification, and Inno Setup compilation.
- Clean per-user installation, installed Core Host health check, native WPF startup-liveness check, and clean uninstall.
- Real public Provider smoke tests; optional key paths run only when repository secrets are configured.
- Portable archive, installer, SHA-256 verification, runtime/license inventory, tracked-secret scan, and candidate artifact upload.

No developer credential, browser cookie, token, password, private-link query value, or user path may be embedded in source, logs, feedback URLs, sidecars, or release packages.
