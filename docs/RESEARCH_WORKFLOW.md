# Research & Culture workflow

FootageFlow v0.9.0 added a local-first research workspace alongside the existing media search. FootageFlow v0.10.0 can also find already-saved research references through its local-only Global Search. Neither capability turns research pages, papers, news stories, or museum records into automatically reusable footage.

## Search modes

- **Media** keeps the existing 17-source footage, image, and audio workflow.
- **Research** searches public reference and culture sources, then displays citation-oriented records.
- **All** keeps Media and Research results in separate groups.

Research ranking reuses FootageFlow's local concept-coverage relevance rules. Wikipedia and Wikidata start with the current interface language and use a bounded English fallback only when the initial result set is sparse. Other research providers receive one compact research query; FootageFlow does not fan one query out into ten languages or stock-footage phrases.

## Research sources

| Source | Access | FootageFlow use | Rights and download rule |
|---|---|---|---|
| Wikipedia | MediaWiki public REST/API | Article discovery, summary, thumbnail preview, canonical URL, Wikidata QID when returned | A preview is not a reusable media license; follow the item to Wikimedia Commons before reusing an image. |
| Wikidata | Public entity search API | Entity, aliases, description, QID, canonical record | Structured reference metadata only. |
| The Met | Public Collection API | Controlled object search/detail batches, object page, small image preview, public-domain metadata | A visible object page is not assumed reusable. **Add as Media** is available only when the provider reports Public Domain and a public original-image URL. |
| Art Institute of Chicago | Anonymous REST + API-provided IIIF base URL | Artwork discovery, metadata, canonical artwork page, IIIF preview | Rights stay unknown unless `is_public_domain` says otherwise. **Add as Media** also requires a public original-image URL. |
| Crossref | Public REST API | Scholarly work metadata, authors, year, container, DOI, optional license URL | Discovery metadata only. FootageFlow never fetches paywalled or restricted full text. |
| GDELT | Public DOC API | News discovery, publisher/domain, date, original article URL | Discovery-only. News images and articles never become downloadable media in FootageFlow. |

All requests use FootageFlow's HTTPS client, bounded timeouts, provider isolation, cancellation, and rate-limit handling. Crossref and AIC requests are spaced conservatively; GDELT's public DOC endpoint is spaced at least five seconds apart. A failed or rate-limited provider does not remove results from the others.

## Research Notes

Choose a project before selecting **Add to Research Notes**. A saved reference contains provider metadata, its canonical URL, citation facts, and a separate editable **My Note** plus tags. Editing a note never overwrites a DOI, QID, source URL, or provider title.

Project Research Notes support text search, type/source filtering, added/published-date sorting, plain-text notes, tags, Copy Citation, Open Original, Find Related Media, deletion, and Refresh Source Metadata. Refresh keeps the user's notes, tags, and added date if the source is unavailable.

## Find Related Media

**Find Related Media** switches back to Media mode and places the small, visible query-hint set from the selected record into the existing editable keyword editor. It then uses the normal 17-media-provider coordinator, relevance ranking, source rules, and download handling. It does not automatically send unbounded entity aliases or invent a new mandatory search concept.

## Export and portable backup

Project Actions offers three report scopes:

1. **Media Sources** — existing attribution and rights information.
2. **Research References** — title, type, source, authors, year, canonical URL, DOI/QID, citation, My Note, tags, and added date.
3. **Combined Project Report** — the two groups plus a separate Research Notes section and media rights warnings.

Markdown, CSV, JSON, and HTML exports use the existing sanitized exporter. HTML is static and escapes user/provider text; CSV guards formula-like values. Secrets, cookies, tokens, signed-query values, absolute private paths, and media binaries are excluded.

Portable `.footageflowproject` manifests now write schema version 2. They remain able to read schema 1 projects, preserve UTF-8 notes/tags and safe canonical URLs across macOS and Windows, and reject unknown future schemas instead of guessing.

## Offline and privacy behavior

Research search and refresh require a network connection. Saved references, citations, notes, filtering, editing, backup/import, and export remain available offline. Research notes are local project data; FootageFlow has no account, analytics, tracking service, or FootageFlow cloud server.
