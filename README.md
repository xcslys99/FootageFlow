# FootageFlow

[English](README.md) · [简体中文](README.zh-CN.md)

**Search footage across 9 sources. macOS + Windows. Free and open source.**

FootageFlow is a privacy-friendly desktop app for discovering, downloading, and organizing real video, image, and audio assets. It is built for documentary, history, country profile, finance, science, and social-video research.

FootageFlow v0.3.0 supports **macOS 15+ on Apple Silicon** and **Windows 11 x64**. Both editions share provider behavior, normalized metadata and rights, filters, attribution formatting, keyword rules, source sidecars, and project persistence.

## What works

- Concurrent, progressive search across Pexels, Pixabay, Wikimedia Commons, Internet Archive, YouTube, NASA, Library of Congress, National Archives, and Europeana
- Advanced filters for source, media type, year, duration, resolution, rights, and direct-download availability
- Multi-select, Select All Visible, batch download through the existing three-slot queue, add to project, retry failed, and copy source information
- Copy Source and Copy Attribution text generated only from provider-supplied metadata
- Video/image preview, favorites, project library, script segmentation, search history, and download history
- A matching `.source.txt` and `.source.json` beside every successful download
- English and Simplified Chinese, with English on first launch and a visible language switcher
- Optional API keys stored only in macOS Keychain or Windows Credential Manager
- No analytics, advertising, tracking, cloud account, paid LLM, OpenAI API, or Codex dependency

YouTube search can use the official Data API when configured. FootageFlow also includes a local, best-effort yt-dlp path for public search and downloads. Downloads may fail because of rate limits, regional restrictions, login requirements, rights restrictions, or platform changes. FootageFlow does not import browser cookies, bypass DRM, or promise that every video is downloadable.

## Screenshots

![FootageFlow main search](docs/images/main-search.png)

![FootageFlow advanced filters](docs/images/advanced-filters.png)

![FootageFlow multi-select and batch download](docs/images/multi-select-batch-download.png)

![FootageFlow provider settings](docs/images/provider-settings.png)

## Install on macOS

1. Download `FootageFlow-0.3.0-macOS-arm64.dmg` from Releases.
2. Open the DMG and drag FootageFlow to Applications.
3. Open FootageFlow. The v0.3.0 build is Ad Hoc signed, not notarized; if macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**.

No terminal command is required for normal use.

## Install on Windows

1. On a Windows 11 x64 PC, download `FootageFlow-Setup-0.3.0-Windows-x64.exe` from Releases.
2. Verify it against the attached `.sha256` file, then double-click the installer.
3. Complete the setup wizard and open FootageFlow from the Start menu.

The installer is self-contained: ordinary users do not need Python, Node.js, Swift, .NET, yt-dlp, or FFmpeg. It is not code-signed yet, so Microsoft Defender SmartScreen may show an unrecognized-app warning. Only continue when the installer came from this repository's official Release and its checksum matches.

## Quick start

1. Open FootageFlow and search immediately; API setup is not required on first launch.
2. Try `Apollo 11` or `World War II`, then open **Advanced Filters** or turn on **Downloadable Only**.
3. Select result cards to batch download, add them to an existing or new project, or copy source information.
4. Use **Copy Attribution** or inspect the original page before publishing.
5. For complete in-app National Archives or Europeana search, add your own key under **Settings → Sources / Providers**.

Default downloads are stored under `~/Movies/FootageFlow/<Project>/` on macOS and `%USERPROFILE%\Videos\FootageFlow\<Project>\` on Windows. You can change the root folder in Settings. Removing a database record does not delete the downloaded media file.

## Supported sources and provider modes

FootageFlow does not require every provider to use the same access method. Some providers offer public APIs without API keys. Some provide a more complete experience when you add your own API key. Limited or best-effort modes remain available where technically and legally possible.

| Provider | Search / API mode | Keyless mode | Download | Rights metadata |
|---|---|---|---|---|
| [Pexels](https://www.pexels.com/api/) | Official API with user key | Direct search, best-effort | Direct media when supplied | API metadata; direct mode may be unknown |
| [Pixabay](https://pixabay.com/api/docs/) | Official API with user key | Direct search, best-effort | Direct media when supplied | API metadata; direct mode may be unknown |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:API) | Public MediaWiki API | Full public interface | Original media when supplied | `extmetadata` when supplied |
| [Internet Archive](https://archive.org/developers/) | Public search and item metadata | Full public interface | Per-item downloadable files | License/rights fields when supplied |
| [YouTube](https://developers.google.com/youtube/v3/getting-started) | Data API with user key | yt-dlp search, best-effort | Conditional yt-dlp download | Usually unavailable; verify original |
| [NASA](https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf) | Official public Images API | No key required | Official asset endpoint when supplied | Item metadata only; never assumed Public Domain |
| [Library of Congress](https://www.loc.gov/apis/) | Official public JSON API | No key required | Official unrestricted resource when supplied | Rights advisory/access fields when supplied |
| [National Archives](https://www.archives.gov/research/catalog/help/api) | Catalog API with user key | Limited: open official search | Digital object when supplied | Restriction/rights fields when supplied |
| [Europeana](https://europeana.atlassian.net/wiki/spaces/EF/pages/2462351393/Accessing+the+APIs) | Search API with user key | Limited: open official search | Direct media URL when supplied | `edmRights`/rights when supplied |

API keys are credentials, not platform logins. They remain on this device, are masked in the UI, and can be added, replaced, tested, or removed under **Settings → Sources / Providers**. Keys are never placed in ordinary settings, logs, source code, Git, telemetry, or request URLs.

## Rights and source safety

FootageFlow never guesses rights or a license. Missing metadata is shown as **Rights / License unknown**. A successful download does not mean commercial reuse is allowed. Internet Archive, NASA, Library of Congress, National Archives, Europeana, and Wikimedia items are not automatically treated as Public Domain. Always verify the original source page before reuse.

This product uses the National Archives Catalog API but is not endorsed or certified by the National Archives and Records Administration.

This project is not affiliated with or endorsed by the listed providers. See [PRIVACY.md](PRIVACY.md) and the [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service).

FootageFlow source code is released under the [MIT License](LICENSE). Media found through the app keeps its own provider-specific copyright and license.

## Build from source

Normal users should install a Release package and do not need development tools. Contributors need Swift 6 and full Xcode on macOS. Windows development uses Swift 6.3.3, .NET 10, the Visual Studio 2022 C++ environment, and Inno Setup 7.

```bash
swift build -c release
swift test
scripts/build_app.sh
scripts/verify_app.sh
```

Windows packaging, clean installation, GUI startup, uninstall, and provider smoke validation run on the Windows 11 x64 GitHub Actions runner. See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and provider-extension guidance.

## Troubleshooting

- **National Archives/Europeana shows Limited Mode**: add your own key for complete in-app search, or use **Open Official Search**.
- **Pexels/Pixabay direct search unavailable**: retry later or optionally add that provider's API key.
- **Too many requests**: wait and retry; FootageFlow does not bypass provider limits.
- **One provider failed**: successful results from other providers remain available.
- **No preview/download button**: use **Open Source Page** when no compatible official media URL is available.
- **Rights are unknown**: verify the current original page; FootageFlow does not infer permissions.
- **Logs**: use **Settings → Open Logs**. Logs do not include API keys.
