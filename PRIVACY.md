# FootageFlow privacy policy

Effective: August 10, 2026

FootageFlow is a local desktop application. It has no FootageFlow account, analytics, advertising, tracking SDK, crash-report upload, telemetry, or background behavioral collection.

## Data stored on the device

FootageFlow stores projects, scripts, favorites, search history, download metadata, settings, cache files, and logs locally. Downloaded media and source sidecars are saved to the folder selected by the user. API keys are stored in the operating system's secure credential store, not in the project database, source code, logs, or plain-text settings.

## Data sent to providers

When a provider is enabled, FootageFlow sends the search terms and normal request metadata needed by that provider. If a Pexels, Pixabay, or YouTube API key is configured, it is sent only to that provider's official API. Without a key, Pexels and Pixabay direct mode requests their ordinary public search pages. Wikimedia Commons and Internet Archive searches do not require an API key.

Those services process requests under their own policies:

- [Pexels Privacy Policy](https://www.pexels.com/privacy-policy/)
- [Pixabay Privacy Policy](https://pixabay.com/service/privacy/)
- [Wikimedia Foundation Privacy Policy](https://foundation.wikimedia.org/wiki/Policy:Privacy_policy)
- [Internet Archive Privacy Policy](https://archive.org/about/terms.php)
- [Google Privacy Policy](https://policies.google.com/privacy)
- [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service)

FootageFlow uses YouTube API Services only to search public video metadata and show thumbnails when the user configures a Data API key. Its separate local yt-dlp adapter can attempt public search and download. It runs with user configuration disabled and does not import browser cookies, use Google OAuth, access a private YouTube account, modify YouTube data, bypass DRM, or bypass login and access controls.

## User controls

- Disable any provider in Settings.
- Remove an API key by clearing the field and saving.
- Clear the search cache and search history from the app.
- Remove favorites, projects, and download-history records.
- Delete downloaded media only through the explicit **Delete Local File** confirmation or directly in Finder.

Removing an app database record does not silently delete downloaded media. Uninstalling the app does not automatically erase user-selected download folders.

## Network and retention

FootageFlow makes requests only when needed for a user action such as search, connection testing, preview, or download. Search results are cached locally for a limited period; Pixabay results are cached for 24 hours. FootageFlow does not operate a server and therefore does not retain a server-side copy of user data.

## Changes

Material privacy changes will be documented in the changelog and this file's effective date will be updated.
