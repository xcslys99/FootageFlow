# Creator workflow UX audit — 2026-09-16

This is a hands-on check of the installed macOS v0.12.1 app, followed by an isolated-data test of the updated local build. The tester followed a documentary creator's workflow rather than judging the UI from screenshots alone. No existing user project or download record was edited.

## Real workflow exercised

1. Searched `西安美食` across the enabled sources. Real cards appeared progressively, including Wikimedia, Internet Archive, and Dailymotion results. An Internet Archive video played in the app with a working timeline.
2. Searched `bank`, changed the result type from Video to Image, and confirmed that the old build falsely reported no matching media. The updated build issued an image search and displayed real Openverse image results.
3. Opened Projects at a normal desktop window size. The old split gave most space to the project list and left the rights audit difficult to reach. The updated build keeps a narrower project list and an independently scrollable detail pane.
4. Analyzed a public 10-second MP4 in Link Downloader. The updated build showed loading during analysis, allowed selecting a project and temporary destination, and routed the download into the existing Download Manager.
5. Verified a 969,201-byte H.264 MP4 with a 10-second duration, paired `.source.txt` and `.source.json` files, the selected project name in the sidecar, and the project/download record after relaunch. Unknown rights remained explicitly unknown.

## Problems fixed in this change

| Observed problem | User impact | Change |
|---|---|---|
| Video → Image used only the already-loaded video candidates | False “no results” message | Re-search the selected type after a submitted query |
| Many language slots contained identical `bank` text | Duplicate Provider requests and longer waits | Deduplicate requests per Provider by normalized text; keep editor slots |
| 22 source toggles and ten discovery-only warnings occupied the first screen | Important cards pushed down; normal limitations looked like failures | Collapse sources and group discovery-only notices |
| A keyless public Provider returned 403 as “Invalid API key” | Misleading advice to configure a nonexistent key | Classify credentialed and keyless 401/403 separately |
| Project details were narrow and could not scroll as a whole | Rights review and project tools were hard to use | Fixed-width project list and scrollable details |
| Link downloads had no visible project choice | Media silently went to Uncategorized | Add a project picker on macOS and Windows |
| Pending link analysis said “Thumbnail unavailable” | Loading looked like an error | Show progress until analysis resolves |

## Validation boundary and remaining issues

- macOS: local unit tests, localization checks, lint, Release build, real GUI search/preview, real public-link analysis/download, sidecars, and project persistence were checked.
- Windows: the shared Swift code and WPF/XAML changes were reviewed and XAML parsed locally. A Windows 11 GUI check is still required; this Mac cannot run WPF.
- A title or description mentioning a place is **not** proof of filming location. For example, an item about “Xi'an Famous Foods” may have been recorded in New York. Creators must check the original page before presenting footage as location-specific evidence. This audit did not add inferred location claims.
- Availability of public websites and yt-dlp extraction varies by time and region. A source-specific failure must remain isolated from other search results.
- This audit does not constitute a new signed/notarized release. Distribution packaging and a Windows runner result are separate gates.
