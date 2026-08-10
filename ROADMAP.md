# FootageFlow roadmap

Roadmap items are intentions, not promises. Provider policies and platform constraints may change implementation details.

## v0.1.x — macOS stabilization

- Crash, networking, cache, download, and localization fixes
- Better accessibility and keyboard navigation
- Notarized release when a suitable Apple Developer identity is available
- Additional provider fixtures and regression coverage

## v0.2 — Windows foundation

- Extract `FootageFlowCore` as a platform-neutral Swift package
- Add Windows system paths and Windows Credential Manager
- Implement Windows-native file dialogs, external opening/reveal, and media preview
- Build Windows UI with feature parity for search, providers, projects, downloads, settings, history, license metadata, and English/Chinese switching
- Produce `FootageFlow-Setup-x.x.x.exe`

## Later

- Additional public providers such as NASA, Library of Congress, and Europeana
- Optional local keyword providers, including offline/local-LLM integrations
- Exportable project manifests and attribution sheets
- Improved duplicate detection and richer archival metadata

Cloud accounts, tracking, subscriptions, automatic publishing, and paid cloud-AI requirements are not planned for the core app.
