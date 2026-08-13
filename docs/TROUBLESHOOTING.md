# Troubleshooting

## A Provider shows Limited Mode

National Archives, Europeana, Coverr, and Vimeo offer fuller in-app behavior only when their required user key or token is configured. Without one, FootageFlow opens the official search page instead of scraping restricted pages.

Use **Settings → Sources / Providers** to add, replace, remove, or test a credential. Credentials are optional for first launch and remain in the operating system's secure credential store.

## Pexels or Pixabay direct search is unavailable

No-key direct search is best-effort. A Provider may temporarily return HTTP 403, change its public page, or block the request. Retry later or add your own optional official API key for a more stable experience. FootageFlow does not bypass CAPTCHA or anti-bot controls.

## Too many requests / HTTP 429

The Provider is rate limiting requests. Wait and retry later. FootageFlow uses bounded retry and pacing but does not bypass limits or loop indefinitely.

## One Provider failed

Successful results from other Providers remain available. Use the Provider status row to retry only the failed source or open its official search where available.

## Thumbnail unavailable

FootageFlow tries normalized Provider thumbnail, preview, poster, and alternate-image candidates. A thumbnail can still fail because it expired, returned HTTP 403/404/429, used an unsupported codec, or came from an unavailable PeerTube instance.

Wait briefly and use **Retry thumbnail** when shown. A thumbnail failure does not make the original result or other Providers unavailable.

## Preview or Download is unavailable

Not every result exposes a compatible preview or direct media URL. Discovery-only Providers intentionally offer **Open Original** instead. For Link Downloader failures, see [Link Downloader](LINK_DOWNLOADER.md).

## The Link Downloader requires login or reports a restriction

FootageFlow does not import browser cookies or bypass login, private media, paid/member content, DRM, or regional controls. Open the original page and use the source's permitted workflow.

## Rights are unknown

The Provider did not supply enough metadata. FootageFlow deliberately does not guess. Open the original page and follow [Rights and attribution](RIGHTS_AND_ATTRIBUTION.md).

## Update checking does not show a dialog

No dialog is expected when the app is current, offline, GitHub is unavailable, or the latest Release is a draft/prerelease. Use **Settings → Software Updates → Check for Updates** for a manual status.

v0.6.0 and earlier cannot check for updates. Install the [latest Release](https://github.com/xcslys99/FootageFlow/releases/latest) manually once. See [Software updates](SOFTWARE_UPDATES.md).

## macOS blocks the first launch

The current macOS build is Ad Hoc signed but not notarized. Confirm that it came from the official GitHub Release, then use **System Settings → Privacy & Security → Open Anyway**. No terminal command is required.

## Windows SmartScreen warns about the installer

The Windows installer is not code-signed yet. Download it only from the official GitHub Release and compare it with the attached SHA-256 checksum before continuing.

## Logs

Use **Settings → Open Logs**. Logs include Provider, request type, time, HTTP status, and redacted error classifications where useful. They do not include API keys, cookies, passwords, project contents, or unredacted sensitive URL values.

If the problem is reproducible, use the [Bug report template](https://github.com/xcslys99/FootageFlow/issues/new?template=bug_report.yml). Remove personal paths, credentials, private media, and project content before attaching diagnostics.
