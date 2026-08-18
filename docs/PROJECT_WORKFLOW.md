# Project workflow, export, and attribution

FootageFlow v0.8.0 adds project-level handoff tools without creating a second download or project system. Projects continue to use the same favorites, downloaded-media records, source sidecars, search history, and Provider metadata that power search and Download Manager.

## Attribution report

Open a project and choose **Project Actions → Attribution Report**. Reports can be exported as Markdown (`.md`), CSV (`.csv`, UTF-8 with BOM by default), JSON (`.json`, versioned schema), or print-friendly HTML (`.html`).

Each entry contains only metadata FootageFlow already has: title, Provider, Provider-native ID, creator/uploader when supplied, original source page, media URL when present, rights/license statement and URL, attribution text, download date, file name, clip range/output preset, and source-sidecar name.

Local absolute paths are excluded by default. They are included only when the user explicitly selects **Include local file paths**. Common accidental credentials, sensitive URL query values, and private local paths in exportable text are redacted. HTML output escapes item text and only turns HTTP(S) values into links; CSV fields are safely quoted and formula-like leading characters are neutralized.

If a project has **Rights Unknown** items or no saved original page, FootageFlow shows a review-or-export warning. It never changes rights metadata or blocks the user from making the final decision.

## Generate Credits

Choose **Generate Credits** to copy a concise or detailed credit list, or save it as text/Markdown. The content is generated from the same Provider-supplied source, creator, license, and attribution metadata as the report. Missing rights remain explicitly unknown.

## Rights Audit

**Rights Audit** summarizes project assets as Rights Known, Attribution Required, Public Domain, Rights Unknown, and Original Page Unavailable. A user can mark an entry as reviewed, but that acknowledgement does not alter the original Provider rights data. Always open the original page and verify current terms before publishing.

## Portable project backup

**Project Backup** creates a `.footageflowproject` file. It is a transparent UTF-8 JSON manifest with a stable `schemaVersion` so it can be inspected and imported on either supported platform.

The backup includes project name/script, script segments and keyword settings, saved assets, selected download metadata, source and rights information, search history, review acknowledgements, and duplicate decisions. It does not include video, image, audio, thumbnails, other large media binaries, API keys, cookies, passwords, tokens, browser credentials, or absolute macOS/Windows local paths.

Only a safe relative filename may be stored as a reference. When imported on another computer, media is intentionally marked **Local media file not found** until the user locates or downloads it again. Imports validate the app marker, schema version, required project name, relative-path safety, and metadata safety before one atomic database write. A name conflict becomes `Project Name (Imported)` rather than overwriting an existing project.

## Duplicate detection

**Find Duplicates** checks project items in this order:

1. same Provider + Provider asset ID
2. normalized original source URL
3. normalized direct download URL
4. SHA-256 for local files when available
5. possible metadata match (title, creator, duration, dimensions)

File hashes are calculated lazily in the background and cached only with local file size/modification data. No cloud upload or server-side fingerprinting occurs. Exact matches are shown ahead of possible matches. You can keep both, mark a group as not duplicate, reset prior decisions, open the original page, reveal an existing local file, or remove an item from the project. Removing an item from a project does not delete the local media file.

## Contact sheet

**Generate Contact Sheet** exports a PNG with 3, 4, or 5 columns, numbered title, Provider, and optional rights status. It reuses cached thumbnails first. For an existing local image it uses the image directly; for an existing local video it may use bundled FFmpeg to read one preview frame around 15% of duration. This is bounded, cancellable, and best-effort: a failed frame renders a neutral placeholder and never changes source media.

## Platform behavior

The report schema, rights audit, portable manifest, URL normalization, duplicate logic, hash behavior, privacy redaction, and contact-sheet plan live in the shared Swift Core. macOS uses SwiftUI/AppKit file and clipboard integration; Windows uses WPF, Windows file dialogs, Explorer, and its native PNG renderer. Both call the same data model and preserve the same project behavior.
