# Creator Workflow Audit — v0.7.3

This audit started from the published v0.7.2 tag and reviewed the existing implementation before any code change. The upgrade is intentionally incremental: no Provider, search, project, localization, download queue, or platform architecture was replaced.

## Capability matrix

| Capability | v0.7.2 audit result | v0.7.3 result | Evidence |
|---|---|---|---|
| Download Clip | Partial validation gap | Complete | Existing full/clip UI, strict range validation, queue identity, cancel/retry/history and sidecars retained; real 10-second clip is now an automated release smoke |
| Smart Search Expansion | Complete | Complete, unchanged | Shared ten-language compound plan, 14-query budget, concept coverage, rate limits, history restoration and local ranking remain single-source Swift |
| Editing-Compatible MP4 | Partial validation gap | Complete | Existing remux/transcode and output verification retained; direct files with unknown resolution now have a final safe format fallback; real H.264/AAC/yuv420p/fast-start output is checked |
| Clipboard Link Detection | Partial | Complete | Still opt-in, foreground-only and local; session-wide URL suppression and bounded cooldown now prevent repeat prompts without storing raw clipboard contents |
| Openverse | Complete | Complete, hardened | Existing images/audio, pagination and item-specific Rights/Attribution retained; requests explicitly exclude mature content and responses are filtered defensively |
| Dailymotion Discovery | Complete | Complete, unchanged | Existing public search, pagination, metadata, thumbnails, unknown-rights handling and discovery-only behavior retained; link analysis remains best-effort |

## Important findings

- The creator clip and MP4 pipeline already used the existing Download Manager and did not need a second queue.
- A direct MP4 whose extractor reports an `unknown` resolution could be rejected by every height-limited format branch. Appending a final `best` branch fixes the direct-media case while preserving preferred AVC/M4A selection.
- Clipboard ignore state previously remembered one clipboard value rather than every URL offered in the app session. Alternating A, B, then A could prompt again.
- Openverse documents mature-content exclusion as the default. v0.7.3 also sends `mature=false` explicitly and refuses an item marked `mature=true`.
- Current Vimeo public extraction can return OAuth 401 when the upstream platform requires an authenticated client. FootageFlow does not load browser cookies or bypass this control; the error is now classified as access/login required.

## Real media verification

The macOS packaged app uses its bundled tools to:

1. Analyze a public YouTube URL.
2. Analyze a public Dailymotion URL.
3. Analyze the W3C-hosted Sintel trailer direct MP4.
4. Download seconds 2–12 through the production `YTDLPService`.
5. Produce and probe an editing-compatible MP4.
6. Verify approximately 10 seconds, H.264, yuv420p, AAC when audio exists, MP4 fast-start, `.source.txt`, and `.source.json`.

The Windows CI runs the equivalent checks through `YtDlpPlatformService`, the packaged Windows tools, and the shared Core Host sidecar writer. A GitHub-hosted IP may be temporarily blocked or rate-limited by YouTube; in that case the release gate requires the limitation to be classified correctly and still requires real Dailymotion/direct-media analysis plus the full clip/output checks. Test media is temporary and is not committed or shipped.

## Security and privacy boundaries

- Clipboard detection remains disabled by default and runs only when the app is active on the Link Downloader page.
- Only normalized public media URLs are kept in volatile session memory; raw clipboard text is not stored, logged, or uploaded.
- yt-dlp always uses `--ignore-config`; FootageFlow never imports browser cookies.
- No DRM, login, private-video, paid-content, regional, or access-control bypass was added.
- Openverse and all other Rights displays continue to use Provider metadata. A successful download never implies a license.

## Release decision

This is v0.7.3 rather than v0.8.0 because all six capabilities already existed. The work fixes bounded stability and validation gaps without adding a new product workflow or changing persisted data.
