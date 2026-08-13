# Link Downloader

FootageFlow's Link Downloader accepts one or more public media-page URLs and tries to detect media that the current bundled yt-dlp and FFmpeg integration can process.

It is a **best-effort** workflow, not a universal downloader. Availability depends on the source, individual media, permissions, regional restrictions, authentication requirements, rate limits, and platform changes.

## Workflow

1. Open **Link Downloader**.
2. Paste one URL or multiple URLs on separate lines.
3. Select **Analyze** or **Analyze All**.
4. Review the detected title, creator/channel, duration, source, thumbnail, formats, and subtitles.
5. Choose the available quality and output options.
6. Select **Download** or **Download Selected**.

Every task enters the same Download Manager used by search results. It keeps the existing progress, speed, cancellation, retry, history, folder reveal, and failure-reason behavior.

## Full media and clips

When the source provides a known duration, FootageFlow can download the full item or a validated start/end clip. Clip ranges accept seconds, `MM:SS`, or `HH:MM:SS`, must stay inside the reported duration, and must be at least 0.5 seconds long.

The chosen scope and clip times are recorded in download history and source sidecars.

## Output choices

Only choices supported by the analyzed item are shown.

- **Original** keeps the resolved source output where practical.
- **Editing-compatible MP4** produces a verified H.264 video with AAC audio when present, `yuv420p`, and fast-start metadata. Compatible MP4 input may be stream-copied; other input may require transcoding.
- **Audio Only** extracts M4A audio when the analyzed source provides a usable audio stream.
- **Subtitles** downloads a selected reported subtitle track when available.
- **Quality** can include Best, 1080p, 720p, or 480p only when the source reports a matching format.

## Supported sites

YouTube, X/Twitter, Vimeo, Dailymotion, and other public sites supported by the bundled yt-dlp build may work. FootageFlow does not claim that every supported extractor, site, account state, or individual URL will work indefinitely.

If media cannot be downloaded, use **Open Original** and follow the source site's own access and reuse rules.

## Safety boundaries

FootageFlow:

- does not import browser cookies or user yt-dlp configuration
- does not bypass DRM, sign-in, private-video controls, paywalls, or member-only access
- rejects URLs containing embedded credentials or sensitive authentication query parameters
- blocks loopback, local, and private-network targets
- excludes formats reported as DRM-protected
- redacts sensitive URL query values before writing sidecars
- never logs passwords, cookies, tokens, or API keys

## Common failure types

- **Unsupported URL**: the bundled analyzer does not support the address.
- **Media unavailable**: the item was removed, made private, or is no longer exposed.
- **Sign-in required**: the source requires an account or permission FootageFlow does not bypass.
- **Region restricted**: the source does not offer the media in the current region.
- **Rate limited**: the source is temporarily rejecting frequent requests.
- **Download unavailable**: metadata may be visible but no usable media action is available.

Technical details are kept in redacted logs. The ordinary interface shows a concise failure reason.

## Files and source records

Successful Link Downloader tasks use the configured FootageFlow download root and produce matching `.source.txt` and `.source.json` files. These records preserve the reported title, source URL, creator, selected format, clip/output settings, rights status, and download date without inventing missing rights metadata.

Read [Rights and attribution](RIGHTS_AND_ATTRIBUTION.md) and [Troubleshooting](TROUBLESHOOTING.md) for reuse and failure guidance.
