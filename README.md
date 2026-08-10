# FootageFlow

[English](README.md) · [简体中文](README.zh-CN.md)

Search. Discover. Download. Organize.

FootageFlow is a privacy-friendly desktop app for finding real video and image assets across several media libraries at once. It is designed for documentary, history, country profile, finance, science, and social-video research.

The current release is a native **macOS 15+ Apple Silicon** app. Windows support is planned after the macOS v0.1.0 release is stable; it is not included in this release.

## What works

- Concurrent search across Pexels, Pixabay, Wikimedia Commons, Internet Archive, and YouTube
- Video and image results with source, creator, resolution, duration, and license metadata when supplied by the provider
- Filters, relevance sorting, deduplication, progressive provider results, and friendly partial-failure states
- Video/image preview, favorites, project library, script segmentation, and search history
- Download queue with progress, speed, cancel, retry, and a maximum of three concurrent downloads
- A matching `.source.txt` and `.source.json` beside each downloaded file
- English and Simplified Chinese with English on first launch and a visible language switcher
- API keys stored in the operating system's secure credential store
- No analytics, advertising, tracking, cloud account, paid LLM, OpenAI API, or Codex dependency

YouTube is used only for official Data API search, thumbnails, metadata, and opening the source page. FootageFlow does not download YouTube videos.

## Screenshots

![FootageFlow search](docs/images/search.png)

![FootageFlow projects](docs/images/projects.png)

## Install on macOS

1. Download `FootageFlow-0.1.0-macOS-arm64.dmg` from Releases.
2. Open the DMG and drag FootageFlow to Applications.
3. Open FootageFlow. The v0.1.0 build is Ad Hoc signed, not notarized; if macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**.

No terminal command is required for normal use.

## Quick start

1. Open FootageFlow. Choose **Set Up Later** if you want to start without API keys.
2. Wikimedia Commons and Internet Archive work without keys.
3. For more sources, open **Settings**, enter a Pexels, Pixabay, or YouTube Data API key, select **Save**, then **Test Connection**.
4. Return to **Quick Search**, enter a topic, review the generated keywords, and select **Search Footage**.
5. Select a project before favoriting or downloading if you want the asset organized into that project.
6. Check every asset's license and original source page before publishing.

Default downloads are stored under `~/Movies/FootageFlow/<Project>/`. You can change the root folder in Settings. Removing a database record never deletes the media file unless you explicitly choose **Delete Local File** and confirm.

## Provider setup

| Provider | API key | Main use |
|---|---:|---|
| [Pexels](https://www.pexels.com/api/) | Required | Modern B-roll video and photos |
| [Pixabay](https://pixabay.com/api/docs/) | Required | Video and images |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:API) | No | Historical images, maps, people, places, and some video |
| [Internet Archive](https://archive.org/developers/) | No | Archival films, newsreels, recordings, and public collections |
| [YouTube Data API](https://developers.google.com/youtube/v3/getting-started) | Required | Research leads and source-page discovery |

API keys are credentials, not platform logins. Availability, quotas, and provider terms remain controlled by each provider.

## License and source safety

FootageFlow never guesses a license. Missing metadata is shown as **License unknown**. Internet Archive items are not assumed to be Public Domain. Always verify the provider's source page and current terms before reuse.

This project is not affiliated with or endorsed by Pexels, Pixabay, Wikimedia Foundation, Internet Archive, Google, or YouTube. See [PRIVACY.md](PRIVACY.md) and the [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service).

FootageFlow source code is released under the [MIT License](LICENSE). Media found through the app keeps its own provider-specific copyright and license.

## Build from source

Requirements: macOS 15+, Swift 6, and Xcode for XCTest.

```bash
swift build -c release
swift test
scripts/build_app.sh
scripts/verify_app.sh
```

Architecture and provider extension instructions are in [DEVELOPMENT.md](DEVELOPMENT.md). Contributions are welcome through [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

- **API key required**: add the key in Settings or disable that provider.
- **Too many requests**: wait and retry; FootageFlow does not bypass provider limits.
- **One provider failed**: other successful provider results remain available.
- **No preview**: use **Open Source Page** when the provider does not expose a compatible stream.
- **Unexpected license**: trust the original provider page, not cached metadata; refresh the search.
- **Logs**: use **Settings → Open Logs**. Logs do not include API keys.
