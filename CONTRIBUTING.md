# Contributing to FootageFlow

Thank you for helping improve FootageFlow. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md) and keep contributions focused, testable, privacy-preserving, and honest about Provider capabilities.

## Report a bug

Use the [Bug report template](https://github.com/xcslys99/FootageFlow/issues/new?template=bug_report.yml) and include:

- FootageFlow version and operating system
- interface language and related Provider, when relevant
- reproducible steps, expected behavior, and actual behavior
- redacted screenshots or logs when useful

Never attach API keys, credentials, cookies, personal paths, private media, project databases, or unredacted logs.

## Request a feature

Use [GitHub Discussions](https://github.com/xcslys99/FootageFlow/discussions/categories/ideas) for early ideas or the Feature Request template for a focused proposal. Describe the creator problem and desired outcome rather than assuming a specific implementation.

Large features and architecture changes should have an Issue before a pull request. Planned work is tracked through the [Roadmap](ROADMAP.md) and public [`roadmap` Issues](https://github.com/xcslys99/FootageFlow/issues?q=is%3Aissue+is%3Aopen+label%3Aroadmap). A Roadmap entry is an intention, not a delivery promise.

## Add or change a Provider

1. Link the current official API documentation and terms.
2. Document authentication, rate limits, caching, attribution, rights, and download rules.
3. Keep Provider, model, and networking logic separate from SwiftUI and WPF views.
4. Map only Provider-supplied metadata. Unknown rights must remain `UNKNOWN`.
5. Add fixed JSON fixtures, parser tests, error cases, and a bounded live smoke path where practical.
6. Keep macOS and Windows behavior aligned through the shared core. Platform-only behavior belongs behind a platform adapter.
7. Update [Provider documentation](docs/PROVIDERS.md) and every affected localization.

FootageFlow does not accept CAPTCHA bypass, Cloudflare bypass, browser-cookie theft, DRM bypass, login circumvention, aggressive scraping, or license inference.

## Before opening a pull request

- Do not add analytics, tracking, advertising, hidden uploads, or mandatory paid AI dependencies.
- Never commit API keys, credentials, personal paths, downloaded media, logs, or local databases.
- Add or update all ten supported localizations together; English fallback must remain complete.
- Keep macOS-only and Windows-only code behind the existing platform boundaries.
- Update tests and documentation for user-visible behavior.
- Keep the pull request limited to one coherent change.

Run the relevant checks:

```bash
scripts/check_markdown_links.sh
scripts/lint.sh
scripts/secret_scan.sh
swift build -c release
swift test
```

On a Mac without full Xcode, XCTest may be unavailable. State that clearly in the pull request and run the offline application self-test when possible. Windows-facing changes must also pass the Windows CI build, platform tests, package verification, and clean install/uninstall checks.

## Good first contribution areas

Smaller documentation corrections, fixture additions, reproducible Provider parsing fixes, accessibility labels, and narrowly scoped test improvements can be good entry points. Check the current Issue scope before starting; large cross-platform refactors should not be labeled or treated as beginner tasks.

## Pull request description

Explain:

- what changed and why
- user-visible impact
- tests and platforms checked
- Provider/API, privacy, rights, and localization implications
- any known limitation

By contributing, you agree that your contribution is licensed under the project's [MIT License](LICENSE).
