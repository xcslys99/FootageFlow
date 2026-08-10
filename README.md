# FootageFlow

[English](README.md) · [简体中文](README.zh-CN.md)

Search. Discover. Download. Organize.

FootageFlow is a privacy-friendly desktop app for finding real video and image assets across several media libraries at once. It is designed for documentary, history, country profile, finance, science, and social-video research.

FootageFlow v0.2.0 supports **macOS 15+ on Apple Silicon** and **Windows 11 x64**. Both editions use the same provider, metadata, license, keyword, source-sidecar, and project-persistence core.

## What works

- Concurrent search across Pexels, Pixabay, Wikimedia Commons, Internet Archive, and YouTube
- Video and image results with source, creator, resolution, duration, and license metadata when supplied by the provider
- Filters, relevance sorting, deduplication, progressive provider results, and friendly partial-failure states
- Video/image preview, favorites, project library, script segmentation, and search history
- Download queue with progress, speed, cancel, retry, and a maximum of three concurrent downloads
- A matching `.source.txt` and `.source.json` beside each downloaded file
- English and Simplified Chinese with English on first launch and a visible language switcher
- Optional API keys stored only in the operating system's secure credential store
- No analytics, advertising, tracking, cloud account, paid LLM, OpenAI API, or Codex dependency

YouTube search can use the official Data API when configured. FootageFlow also includes a local, best-effort yt-dlp path for public search and downloads. Downloads can fail because of rate limits, regional restrictions, login requirements, rights restrictions, or platform changes. FootageFlow does not import browser cookies, bypass DRM, or promise that every video is downloadable.

## Screenshots

![FootageFlow search](docs/images/search.png)

![FootageFlow projects](docs/images/projects.png)

## Install on macOS

1. Download `FootageFlow-0.2.0-macOS-arm64.dmg` from Releases.
2. Open the DMG and drag FootageFlow to Applications.
3. Open FootageFlow. The v0.2.0 build is Ad Hoc signed, not notarized; if macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**.

No terminal command is required for normal use.

## Install on Windows

1. On a Windows 11 x64 PC, download `FootageFlow-Setup-0.2.0-Windows-x64.exe` from Releases.
2. Verify it against the attached `.sha256` file, then double-click the installer.
3. Complete the setup wizard and open FootageFlow from the Start menu.

The installer is self-contained: ordinary users do not need Python, Node.js, Swift, .NET, yt-dlp, or FFmpeg. It is not code-signed yet, so Microsoft Defender SmartScreen may display an unrecognized-app warning. Only continue when the installer came from this repository's official Release and its checksum matches.

## Quick start

1. Open FootageFlow and search immediately; API setup is not required on first launch.
2. Wikimedia Commons and Internet Archive use public interfaces. Pexels and Pixabay attempt direct searches when no key is configured.
3. For more reliable Pexels or Pixabay results, open **Settings → Sources / Providers**, optionally add your own API key, then select **Test Connection**.
4. Return to **Quick Search**, enter a topic, review the generated keywords, and select **Search Footage**.
5. Select a project before favoriting or downloading if you want the asset organized into that project.
6. Check every asset's license and original source page before publishing.

Default downloads are stored under `~/Movies/FootageFlow/<Project>/` on macOS and `%USERPROFILE%\Videos\FootageFlow\<Project>\` on Windows. You can change the root folder in Settings. Removing a database record does not delete the downloaded media file.

## Provider modes

| Provider | Preferred mode | Without a key / fallback | Download capability |
|---|---|---|---|
| [Pexels](https://www.pexels.com/api/) | Official API (recommended) | Direct search (best-effort) | When a direct media URL is supplied |
| [Pixabay](https://pixabay.com/api/docs/) | Official API (recommended) | Direct search (best-effort) | When a direct media URL is supplied |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:API) | Public MediaWiki API | Public API | According to item metadata |
| [Internet Archive](https://archive.org/developers/) | Public search and metadata interfaces | Public interface | According to each item's files and rights |
| [YouTube](https://developers.google.com/youtube/v3/getting-started) | Data API search when configured | yt-dlp search (best-effort) | yt-dlp best-effort; not guaranteed |

API keys are optional. FootageFlow works without requiring Pexels or Pixabay API keys. However, direct searches can occasionally be limited by the provider. Users who frequently search these services can optionally add their own API keys for a more reliable experience.

API keys are credentials, not platform logins. They remain on this device, are masked in the UI, and can be replaced, tested, or removed under **Settings → Sources / Providers**. Availability, quotas, and provider terms remain controlled by each provider.

## License and source safety

FootageFlow never guesses a license. Missing metadata is shown as **License unknown**. Internet Archive items are not assumed to be Public Domain. Always verify the provider's source page and current terms before reuse.

This project is not affiliated with or endorsed by Pexels, Pixabay, Wikimedia Foundation, Internet Archive, Google, or YouTube. See [PRIVACY.md](PRIVACY.md) and the [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service).

FootageFlow source code is released under the [MIT License](LICENSE). Media found through the app keeps its own provider-specific copyright and license.

## Build from source

Normal users should install a Release package and do not need development tools. Contributors need Swift 6 and full Xcode on macOS. Windows development uses Swift 6.3.3, .NET 10, the Visual Studio 2022 C++ environment, and Inno Setup 7.

```bash
swift build -c release
swift test
scripts/build_app.sh
scripts/verify_app.sh
```

Windows packaging and clean-install validation run on the repository's Windows 11 x64 GitHub Actions runner. See [DEVELOPMENT.md](DEVELOPMENT.md) for the exact commands and platform split.

Architecture and provider extension instructions are in [DEVELOPMENT.md](DEVELOPMENT.md). Contributions are welcome through [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

- **Pexels/Pixabay direct search unavailable**: retry later or optionally add that provider's API key for a more reliable mode.
- **Too many requests**: wait and retry; FootageFlow does not bypass provider limits.
- **One provider failed**: other successful provider results remain available.
- **No preview**: use **Open Source Page** when the provider does not expose a compatible stream.
- **Unexpected license**: trust the original provider page, not cached metadata; refresh the search.
- **Logs**: use **Settings → Open Logs**. Logs do not include API keys.
