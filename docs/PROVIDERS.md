# Provider Modes and API Behavior

FootageFlow searches 17 sources through the most stable access method each source reasonably supports. It does not force every source into one API or download model.

The product principle is: **search as broadly as possible, download where reasonably supported**.

## Mode glossary

- **Official API**: A documented Provider API. Some require a user-supplied key or token.
- **Public interface**: An official public endpoint that does not currently require a key.
- **Direct search, best-effort**: A bounded public-page search used without a key. It does not bypass CAPTCHA, Cloudflare, login, cookies, or access controls and may stop working when the Provider changes or blocks it.
- **Limited discovery**: FootageFlow can open the Provider's official search but does not scrape restricted pages.
- **Discovery only**: Results help users find original material; FootageFlow does not offer a direct download action.
- **Conditional download**: Download depends on the specific item, its metadata, access controls, and the current upstream tool behavior.

## Capability matrix

| Provider | Search mode | Keyless behavior | Download | Rights metadata | Primary action |
|---|---|---|---|---|---|
| [Pexels](https://www.pexels.com/api/) | Official API with user key | Direct search, best-effort | Direct media when supplied | API metadata; direct mode may be unknown | Search / Download / Open Original |
| [Pixabay](https://pixabay.com/api/docs/) | Official API with user key | Direct search, best-effort | Direct media when supplied | API metadata; direct mode may be unknown | Search / Download / Open Original |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:API) | Public MediaWiki API | Full public interface | Original media when supplied | `extmetadata` when supplied | Search / Download / Open Original |
| [Internet Archive](https://archive.org/developers/) | Public search and item metadata | Full public interface | Per-item downloadable files | License or rights fields when supplied | Search / Download / Open Original |
| [YouTube](https://developers.google.com/youtube/v3/getting-started) | Data API with user key | Local yt-dlp search, best-effort | Conditional yt-dlp download | Usually unavailable; verify original | Search / Conditional Download / Open Original |
| [NASA](https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf) | Official public Images API | No key required | Official asset when supplied | Item metadata only; never assumed Public Domain | Search / Download / Open Original |
| [Library of Congress](https://www.loc.gov/apis/) | Official public JSON API | No key required | Unrestricted official resource when supplied | Rights advisory and access fields when supplied | Search / Download / Open Original |
| [National Archives](https://www.archives.gov/research/catalog/help/api) | Catalog API with user key | Limited: open official search | Digital object when supplied | Restriction and rights fields when supplied | Search with key / Open Official Search |
| [Europeana](https://europeana.atlassian.net/wiki/spaces/EF/pages/2462351393/Accessing+the+APIs) | Search API with user key | Limited: open official search | Direct media when supplied | `edmRights` or rights fields when supplied | Search with key / Open Official Search |
| [PeerTube / SepiaSearch](https://docs.joinpeertube.org/api-rest-reference.html) | Public SepiaSearch API | No key required | Discovery only | Per-video license metadata when supplied | Search / Open Original |
| [Videvo](https://www.videvo.net/) | Limited discovery | Open official search | Open Original only | Verify every item | Open Official Search |
| [Videezy](https://www.videezy.com/) | Limited discovery | Open official search | Open Original only | Free items may require attribution; verify original | Open Official Search |
| [Mixkit](https://mixkit.co/) | Limited discovery | Open official search | Open Original only | Free and restricted terms vary; verify original | Open Official Search |
| [Coverr](https://api.coverr.co/docs) | Official API with user key | Limited: open official search | API media URL when supplied | Provider API/license metadata | Search with key / Open Official Search |
| [Vimeo](https://developer.vimeo.com/api/reference) | Official API with user token | Limited: open official search | Discovery only by default | Only explicit license metadata | Search with token / Open Official Search |
| [Openverse](https://api.openverse.org/) | Public image/audio API | Anonymous access | Original media when supplied | Item license, creator, URL, and attribution metadata | Search / Download / Open Original |
| [Dailymotion](https://developers.dailymotion.com/reference/api-list-videos) | Public video discovery endpoint | No key required for current public fields | Discovery only in search; Link Downloader is separate and best-effort | Unknown unless explicitly supplied | Search / Open Original |

## API keys and secure storage

API keys are optional for normal first use. Pexels and Pixabay automatically use their official APIs when a valid local key exists and direct best-effort search when it does not. An official API failure does not silently downgrade to direct search. National Archives, Europeana, Coverr, and Vimeo use their supported key or no-key mode.

Keys are stored only in macOS Keychain or Windows Credential Manager. They are masked in the interface and are never written to source code, Git, ordinary settings, logs, telemetry, request URLs, or crash reports.

## Failure isolation, timeouts, and rate limits

Providers run as independent tasks. A timeout, invalid key, HTTP 403, HTTP 429, parsing failure, or upstream outage from one source does not discard results from other sources.

FootageFlow uses bounded timeouts, cancellation, Provider-specific pacing, and limited retry/backoff for transient failures. It does not loop indefinitely or bypass Provider controls. A rate-limited Provider is shown with a readable status and can be retried later.

## Rights and downloads

A Download button appears only when the Provider or the supported download adapter supplies a usable action. Discovery-only results use **Open Original**. A successful download never changes the item's rights status.

Missing license or rights metadata remains unknown. Read [Rights and attribution](RIGHTS_AND_ATTRIBUTION.md) before reusing media.

This product uses the National Archives Catalog API but is not endorsed or certified by the National Archives and Records Administration.
