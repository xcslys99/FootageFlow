# Accessibility

FootageFlow is designed to remain usable without a mouse. Native macOS controls expose VoiceOver names and native Windows controls expose UI Automation names for core actions, search fields, result cards, selection, download controls, status, dialogs, and Workspace panels.

## Manual verification checklist

Run this checklist on a clean release candidate in both Light and Dark Mode where available:

1. Navigate Search, filters, a result card, Projects, Research Notes, Downloads, Settings, Command Palette, Global Search, Saved Searches, Smart Collections, and Provider Status using only the keyboard.
2. Confirm focus is visible, hidden content is skipped, Escape closes the active transient panel, and focus returns to a useful control.
3. With VoiceOver on macOS and Narrator on Windows, confirm the name/state of search fields, filters, result title/provider/rights/download availability, selected count, download progress/errors, source state, Command Palette result, Global Search result type, and update dialog controls.
4. Verify rights, failed download, provider-unavailable, selected, duplicate, missing-file, and update states are conveyed in text rather than color alone.
5. Repeat the core flows in all ten supported UI languages. A missing optional translation must fall back to English text, never a raw localization key.

Please report barriers through the repository’s accessibility issue template or a regular bug report. FootageFlow does not collect assistive-technology usage data.
