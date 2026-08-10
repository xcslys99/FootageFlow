# Windows architecture audit

Status: Windows 11 x64 in development for FootageFlow v0.2.0. This document does not claim that the Windows release is complete or supported.

## Current shared code

The five `MediaProvider` implementations, API/direct-mode selection, `HTTPClient`, normalized `MediaAsset`, license mapping, provider capabilities and errors, keyword rules, deduplication, filename suggestions, sidecar generation, path roots, logging redaction, and Codable persistence are platform-neutral Swift. Pexels, Pixabay, Wikimedia Commons, Internet Archive, and YouTube Data API therefore have one business implementation.

`PersistentStore` owns project, segment, favorite, history, and download-record behavior. The macOS `DataStore` is now a small Combine presentation facade over this shared repository. Windows calls the same repository through the local Core Host.

## macOS-only code

SwiftUI views, `SearchViewModel`, AppKit windows and file panels, AVKit preview, Apple Translation, Security.framework Keychain, macOS `Process`, Finder reveal, and the existing URLSession download UI remain macOS-only. Swift Package Manager excludes these sources when building on Windows; their implementation is otherwise unchanged.

## Reuse estimate

Approximately 75% of core behavior is shared after the extraction. Provider and license behavior is effectively 100% shared. Presentation, secure storage, external-process lifecycle, preview, dialogs, and operating-system integration are intentionally implemented per platform.

## Windows UI technology

WPF on .NET 10 is used for the Windows 11 x64 interface. WPF provides a native Windows window/control model, XAML data binding, MediaElement preview, accessibility, high-DPI behavior, and a self-contained deployment option. It avoids an Electron runtime and does not require the user to install .NET.

## Shared architecture

```text
WPF UI and Windows adapters
        |
        | JSON over stdin/stdout (secrets never in argv)
        v
Swift FootageFlowCore.exe
        |
        +-- ProviderFactory and five providers
        +-- models, license rules, keywords, dedupe
        +-- PersistentStore and source sidecars
```

The WPF orchestrator launches provider requests independently. Whichever provider finishes first can be displayed first; cancellation or timeout kills only that local Core Host process. Pexels/Pixabay mode selection still happens in `ProviderFactory`. Without a key they use best-effort direct search. A configured key selects only the official API. YouTube's Windows process adapter runs the bundled yt-dlp with `--ignore-config` and no cookie import, then sends its JSON to the shared Swift mapper.

## Windows-only responsibilities

- Windows Credential Manager for API keys.
- `%LOCALAPPDATA%\FootageFlow` settings/log/database roots and the user's Videos folder for downloads.
- Windows-invalid and reserved filename protection, long-path manifest support, and conflict-safe filenames.
- Explorer open/reveal, folder chooser, WPF MediaElement/image preview.
- Bounded direct-download queue and yt-dlp child-process cancellation.
- Self-contained .NET publish, Swift runtime DLL collection, bundled yt-dlp, and Inno Setup installer.

## Migration risks

- Swift Foundation behavior and runtime DLL packaging differ on Windows and must be verified on a Windows runner.
- WPF cannot reuse SwiftUI/AppKit view code; only business behavior is shared.
- yt-dlp is best-effort and changes upstream. It remains checksum-pinned and must not load browser cookies or user config.
- An unsigned installer can trigger Microsoft Defender SmartScreen. The release must describe signing status honestly.
- Windows path rules, Chinese/space paths, cancellation, clean install, and uninstall need Windows-native acceptance tests.

## Expected macOS changes

Only narrow shared-core extraction, conditional SwiftPM source selection, and cross-platform Foundation imports are expected. Every Windows commit continues to run the full macOS Release build, XCTest suite, app-bundle signing check, binary privacy scan, and offline self-test.

## Version plan

- v0.1.0 remains unchanged and macOS-only.
- v0.2.0 is the first planned feature release with Windows 11 x64 support.
- README will continue to say “Windows — In development” until the setup executable, checksums, clean install/uninstall, provider tests, and final cross-platform regression tests pass.
