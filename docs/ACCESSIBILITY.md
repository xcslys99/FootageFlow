# Accessibility

FootageFlow is designed to remain usable without a mouse. It uses native SwiftUI accessibility on macOS and WPF UI Automation on Windows. This includes meaningful names for icon-only actions, result-card controls, source toggles, download state, filters, projects, link input, and the update dialog.

## Keyboard behavior

- `Tab` and `Shift+Tab` follow the visual work order: navigation, page controls, filters, results, then actions.
- `Enter` activates the focused primary action. `Space` toggles checkboxes and standard native controls.
- `Esc` closes Command Palette and Global Search without trapping keyboard focus. On Windows, the invoking control receives focus again after closing.
- **Clear Filters** resets only filters; it never removes the current query, keyword plan, project choice, or loaded results.
- On macOS, FootageFlow uses the system’s native keyboard focus behavior. On Windows, focusable controls have a visible accent outline.

See [Keyboard shortcuts](KEYBOARD_SHORTCUTS.md) for direct navigation shortcuts.

## Screen readers and status

- VoiceOver and Windows Narrator can identify search inputs, filter controls, source toggles, result-card actions, project list, download progress/state, and update information.
- Download progress and result counts expose text and values instead of relying on color alone.
- Decorative update artwork is hidden from the accessibility tree.
- The update dialog starts at **Not Now**, contains a keyboard-reachable scrollable **What’s New** area, and labels **View Update** as opening the official Release page. It does not download or install an update inside FootageFlow.

All new user-facing accessibility text is available in English, 简体中文, 繁體中文, Español, Português (Brasil), 日本語, 한국어, Deutsch, Français, and Русский. Missing optional copy falls back to English rather than showing a raw localization key.

## Release-candidate manual checklist

Automated tests verify localization coverage, filter-reset behavior, keyboard command routing, and Windows UI Automation declarations. They do not replace a real screen-reader check.

### macOS

1. Turn on Full Keyboard Access in macOS settings if it is disabled, then use only `Tab`, `Shift+Tab`, `Enter`, `Space`, and the shortcuts below.
2. Use `⌘F` to focus Quick Search; enter a query, press Return, reach filters, use **Clear Filters**, tab into a result card, preview/save/download/open its source, and return to the search field.
3. Use `⌘O` for Projects and `⌘⇧D` for Downloads. Create/select a project, reach its main actions and assets, then cancel/retry/reveal a download where available.
4. Use `⌘,` for Settings. Move through language, provider toggles, API-key controls, download folder, and manual update check.
5. Turn on VoiceOver with `⌘F5` (or the configured accessibility shortcut) and repeat steps 2–4. Confirm icon-only buttons are named, selected/failed/downloading states are spoken, and no keyboard trap occurs.
6. Open an available update dialog from Settings. Confirm the initial focus is **Not Now**, Release Notes are readable, Tab reaches **View Update**, and closing does not trap keyboard focus.

### Windows 11

1. Use `Ctrl+F` to focus Quick Search; complete the same search, filter, result-card, project, download, and settings flow with `Tab`, `Shift+Tab`, `Enter`, `Space`, and `Esc` only.
2. Verify the accent focus outline remains visible for buttons, text inputs, comboboxes, checkboxes, password fields, and lists.
3. Open Command Palette with `Ctrl+K` and Global Search with `Ctrl+Shift+G`. Use Down/Up and Enter to act on a result, then Escape to close; focus should return to the invoking control.
4. Turn on Narrator with `Win+Ctrl+Enter` and repeat the core flow. Confirm it reports control names, checkbox state, source/provider state, result actions, download progress/error, and update details.
5. Open an available update dialog. Confirm **Not Now** receives initial focus, Escape closes it, **View Update** is labelled as a browser action, and focus returns to the main window afterwards.

Please report barriers through the repository’s accessibility issue template or a regular bug report. FootageFlow does not collect assistive-technology usage data.
