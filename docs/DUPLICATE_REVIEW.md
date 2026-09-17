# Smart Duplicate Review

Status: v0.13.0 development candidate; not a published release.

## What the group means

After normal provider search, the existing relevance gate, ranking, and advanced filters, FootageFlow locally reviews the visible media results. The original result list is retained. A duplicate group is a presentation of two or more cards that have evidence of shared or similar media. The summary counts original results, visible unique entries (groups plus standalone cards), and groups. **All Results** restores a flat view without discarding any item.

- **Exact match:** a shared native provider ID, canonical source URL, canonical download URL, or explicit canonical media ID.
- **Likely same footage:** strongly corroborated title, duration and creator/filename metadata, or a close local thumbnail fingerprint backed by compatible duration and title or creator.
- **Possibly similar:** substantial title overlap and compatible duration without enough corroboration for a stronger statement.

Similarity is probabilistic. Different edits, crops, and transcodes may not group; unrelated items can occasionally be suggested together. Expand a group and inspect every version before using it.

## Recommended version and rights

The recommended card is picked from metadata completeness, traceable source, direct download, duration and resolution information. Public Domain is **not** a universal priority, and the recommendation is **not** a declaration that an item is safe, copyright-free, or permitted for commercial use. Each card retains its own Provider, rights, attribution, source URL and actions. An Unknown rights state is never copied from a neighboring card. Verify the actual source terms before publishing.

## Controls and accessibility

Detection and default collapsing are on by default and can be changed in Settings → Duplicate Review. The search results provide Grouped / All Results. The group control expands its other versions, while the recommended version remains visible even when collapsed. All original result actions remain on their cards: preview, source opening, favorite, project selection, download where offered, source copy and attribution copy. Keyboard focus and native screen-reader semantics follow the existing macOS and Windows card controls. New labels are translated into all ten interface languages.

## Local processing, performance and failure behavior

No user project, search history, thumbnail or media is uploaded to a FootageFlow service for duplicate analysis. The metadata scan uses indexed IDs, URLs, title-token/duration buckets and thumbnail-hash bands instead of all-pairs comparison. It runs after relevance and filtering, off the initial result-display path. Only plausible thumbnail candidates are loaded through the existing safe thumbnail pipeline; at most 80 image candidates are considered per analysis, and no full video is fetched. Thumbnail decode is bounded to a 4096-pixel side and 16 million source pixels. Blank images are rejected as evidence. The fingerprint cache is memory-only and bounded to 240 URLs; clearing cache in macOS Settings clears it, and restarting either app discards it. The cache contains no API keys, cookies or full media.

An invalid thumbnail, unavailable source, cancellation, or failed fingerprint scan cannot fail the search. Original cards remain visible, and metadata-only groups can still be shown. Group evidence is not written into `.footageflowproject`; older project files need no schema migration. The existing Project duplicate scan and its user decisions remain separate workflows but share URL canonicalization and evidence normalization.

## Implementation boundary

`SearchDuplicateAnalyzer` in the Swift Shared Core owns the grouping and recommendation rules for both desktop platforms. macOS and Windows only decode local thumbnails into small luminance samples and present the returned groups. The Windows host action is `analyzeSearchDuplicates`. There is no cloud similarity service or AI API.

## Release-candidate manual acceptance checklist

Run on an isolated profile on macOS Apple Silicon and Windows 11 x64, using real search results rather than fixture cards. Record the query, result count, group count, build hash and OS version.

1. Search a broad real topic, wait for partial and then completed results, and verify that result cards appear before background grouping.
2. Check that the summary counts original results and that Grouped / All Results never loses a candidate.
3. Expand a group with two sources. Preview, open original, favorite, select, download when offered, copy source, and copy attribution from each original card.
4. Compare an Unknown-rights version with a known-rights version. Confirm that the former remains Unknown in both views and in its copied source text.
5. Change source, media type, year, duration, resolution, rights and Downloadable Only filters; confirm groups contain only currently visible eligible cards. Switch Precise / Balanced / Broad without resurrecting filtered-out content.
6. Toggle duplicate detection and default collapse in Settings, relaunch, and check persistence and the flat-result fallback.
7. Use only the keyboard to reach the view switch, group disclosure, recommended card, other cards and each card action. Verify clear visible focus.
8. With VoiceOver or Windows Narrator, verify the group label, version count, expanded/collapsed state, recommended-version label, individual Provider and rights, and all action names.
9. Switch all ten UI languages. Verify new labels have translations, while source-provided titles and licenses remain unaltered.
10. Disconnect the network during a thumbnail request and cancel or restart a search. Cards must remain usable, with no crash or modal duplicate-analysis error.

Automated tests and CI cannot stand in for the two real screen-reader sessions in steps 7–8.
