# Thumbnail Pipeline Audit — v0.5.0

Audit date: 2026-08-11

## Root causes

1. PeerTube's current search model can expose `thumbnails[].fileUrl`, `thumbnailUrl`, `thumbnailPath`, `previewUrl`, and `previewPath`. The old parser decoded only `thumbnailUrl`; a relative or missing value was discarded.
2. PeerTube is decentralized. A relative `/lazy-static/...` path belongs to the result's `channel.host`, `account.host`, or source-page origin, not to `sepiasearch.org`.
3. Both desktop shells had one-shot presentation: SwiftUI `AsyncImage` and WPF `Image.Source` received one URL. There was no candidate fallback, controlled User-Agent, content validation, short failure cache, or retry state.
4. The old search cache could retain a stale single thumbnail URL for 30 minutes.
5. Providers sometimes return a malformed or expired first image while also returning a valid alternate. A live Library of Congress result reproduced this: the first candidate failed, while a later `tile.loc.gov` image decoded correctly.
6. Image content negotiation is real. In the live sample Pexels returned AVIF through a `.jpeg` URL and YouTube returned WebP through a `.jpg` URL. File extensions alone are not sufficient.

## Provider field audit

| Provider | Raw thumbnail metadata used | Resolution and fallback | 2026-08-11 validation |
|---|---|---|---|
| Pexels | API `video.image`; photo `src.medium`, `src.large`, `src.original`; direct-page `srcset`, `poster`, lazy/src attributes | All candidates normalized; direct page source is the base | Keyless direct sample 5/5 decoded, AVIF negotiated on macOS; official API covered by fixture |
| Pixabay | Video file `thumbnail`; image `webformatURL`, `largeImageURL`, `fullHDURL`, `imageURL`; direct-page markup | Ordered candidates | Keyless direct sample 5/5 JPEG; official API covered by fixture |
| Wikimedia Commons | MediaWiki `thumburl`, original `url` | Thumb then original | Live 5/5 JPEG |
| Internet Archive | `services/img/{identifier}`, then `download/{identifier}/__ia_thumb.jpg` | Two official archive candidates | Live 5/5 JPEG |
| YouTube | Data API high/medium/default; yt-dlp thumbnail list; deterministic `hqdefault`/`mqdefault` fallback | Ordered by size, then static fallback | Keyless yt-dlp sample 5/5 WebP; Data API fixture covered |
| NASA | Search `links` with `rel=preview`; asset-manifest image files | Preview and manifest images | Live 5/5 JPEG |
| Library of Congress | Result `image_url[]`, resource `image` | Result images first, then resource image | Live primary 3/5, candidate pipeline 4/5; remaining result had no image metadata |
| National Archives | Digital object `thumbnailLink`, `thumbnailUrl`, `previewUrl`, then image object file | Ordered object candidates | Fixed API fixture; live skipped because no local key |
| Europeana | `edmPreview[]`, then `edmIsShownBy` for images | Ordered Europeana candidates | Fixed API fixture; live skipped because no local key |
| PeerTube / SepiaSearch | `thumbnails[].fileUrl`, `thumbnailUrl`, `thumbnailPath`, `previewUrl`, `previewPath` | Relative values use the video's actual instance; newer thumbnail array preferred | Live 5/5 JPEG across `peertube.luanti.ru`, `makertube.net`, and `video.igem.org`; relative/different-instance fixture passes |
| Videvo | No in-app result object in current limited mode | Opens official search only | No thumbnail Card is created |
| Videezy | No in-app result object in current limited mode | Opens official search only | No thumbnail Card is created |
| Mixkit | No in-app result object in current limited mode | Opens official search only | No thumbnail Card is created |
| Coverr | API `thumbnail` | Absolute candidate plus response validation | Fixed official API fixture; live skipped because no local key |
| Vimeo | `pictures.sizes[].link` | Largest-to-smallest ordered candidates | Fixed official API fixture; live skipped because no local token |

Every normalized candidate is absolute HTTPS. HTTP values are upgraded only to the same HTTPS host; FootageFlow does not globally disable ATS and does not fall back to insecure HTTP.

## Live evidence

Command:

```text
FootageFlow --thumbnail-smoke city
```

The public/keyless sample contained 40 Cards from Internet Archive, Library of Congress, NASA, PeerTube, Pexels, Pixabay, Wikimedia Commons, and YouTube.

- Former single-primary behavior: 38/40 decoded (95.0%).
- New ordered-candidate pipeline: 39/40 decoded (97.5%).
- The remaining Card did not contain any thumbnail metadata; no URL was invented.
- PeerTube/SepiaSearch in this run: 5/5 decoded, all from the result's own instance, never SepiaSearch.
- A wider pre-fix PeerTube network probe across 60 results returned 56 valid JPEG responses. The four failures were decentralized-instance TLS, empty-response, or timeout failures. These upstream instance failures remain isolated and retryable.

The 95.0% baseline is a conservative replay of the former one-URL UI using the now-normalized primary field. Relative-only PeerTube fixture coverage is more direct: the former parser produced no URL, while the new resolver produces the correct instance URL.

## Cache and UI behavior

- Loading shows an indeterminate progress/skeleton state.
- Failure text appears only after all trusted candidates fail.
- Retry clears only the short failure entry; successful images remain cached.
- Success cache TTL is six hours and failure cache TTL is 45 seconds.
- 403, 404, 429, timeout, HTML, JSON, empty, oversized, and decode-failed responses are never stored as successful images.
- macOS and Windows Cards, download rows, and Link Downloader previews use the same behavior; no UI Card constructs a provider URL.

## Remaining boundaries

- A dead or TLS-broken decentralized PeerTube instance cannot be repaired by FootageFlow; the failure is isolated and retryable.
- Some results genuinely contain no thumbnail metadata.
- Windows requests JPEG/PNG first to avoid unnecessary codec dependency. Native WebP/AVIF responses are detected and passed to WIC; if the user's Windows installation lacks the relevant codec and no alternate candidate exists, the Card reports an unavailable thumbnail rather than caching invalid data.
- Keyed live modes are exercised only when the corresponding user or CI secret is present. Fixed fixtures cover their parsing without storing keys.
