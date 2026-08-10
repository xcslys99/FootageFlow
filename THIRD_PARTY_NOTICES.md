# Third-party notices

FootageFlow uses Apple system frameworks and the Swift standard libraries supplied by the operating system/toolchain.

The unreleased cross-platform branch bundles the platform executable from [yt-dlp 2026.07.04](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.07.04) for best-effort YouTube interoperability. yt-dlp is distributed under [The Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE). Each build downloads the fixed platform release and verifies its SHA-256 before packaging. FootageFlow does not bundle FFmpeg.

The Windows package contains the Swift runtime libraries from the official Swift toolchain. Swift is distributed under the [Apache License 2.0 with Runtime Library Exception](https://www.swift.org/LICENSE.txt). The self-contained Windows interface includes .NET 10.0.10 and WPF, distributed by Microsoft under the [MIT License](https://github.com/dotnet/runtime/blob/main/LICENSE.TXT) and their accompanying third-party notices. Copies of the official Swift and .NET license files are included under the packaged `Licenses` directory.

The app interoperates with independent services through their public APIs:

- Pexels API
- Pixabay API
- Wikimedia Commons / MediaWiki API
- Internet Archive APIs
- YouTube Data API
- Public Pexels/Pixabay result pages in best-effort direct mode
- Public YouTube pages through the local yt-dlp executable

Provider names and marks belong to their respective owners. Their appearance identifies the source of a result and does not imply sponsorship or endorsement.

Media returned by a provider is not covered by FootageFlow's MIT License. Each item remains subject to the license, rights statement, attribution requirements, and terms shown by its original provider.

The project Code of Conduct is adapted from Contributor Covenant 2.1, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
