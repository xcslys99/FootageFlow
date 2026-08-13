# Software Updates

FootageFlow checks this repository's public GitHub Releases directly. It has no update server of its own and never forces an update.

## Current behavior

- v0.7.0 and later can compare the installed semantic version with the latest stable GitHub Release.
- v0.7.4 and later run one asynchronous check after the main window loads on every app launch.
- Only a newer stable release is considered. Drafts and prereleases are ignored.
- An outdated online installation shows the current version, latest version, publication date, and the real Release Notes from GitHub.
- **View Update** opens only the official `https://github.com/xcslys99/FootageFlow/releases/` page for that release.
- **Not Now** closes the dialog for the current app session only.
- The same app session shows at most one automatic update dialog.
- If the app is still outdated after a complete restart, it checks and reminds again.

FootageFlow does not silently download, silently install, replace the application, force a restart, or prevent continued use of the installed version.

## Manual checks

Use **Settings → Software Updates → Check for Updates** at any time. Manual checks can report that the app is current or show a friendly error when GitHub is unavailable.

## Offline and GitHub failures

Automatic startup failures stay silent. No dialog interrupts normal use when the device is offline or GitHub returns a timeout, rate limit, server error, or invalid response.

## Legacy installations

v0.6.0 and earlier do not contain an update checker and cannot receive this behavior remotely. Install the [latest stable Release](https://github.com/xcslys99/FootageFlow/releases/latest) manually once. Later releases can then notify you about future stable updates.

The old v0.7.0 24-hour **Remind Later** behavior is retained in the historical [CHANGELOG](../CHANGELOG.md). v0.7.4 superseded it with session-only **Not Now** behavior.

## Privacy and security

The startup check sends only the request needed to read this repository's public GitHub Release metadata. It does not send projects, scripts, search/download history, clipboard content, API keys, local paths, or personal files.

Release Notes are converted from bounded Markdown into inert text before display. Release URLs are accepted only when they use HTTPS and belong to this repository's official Releases path.
