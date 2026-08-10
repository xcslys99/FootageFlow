# Contributing to FootageFlow

Thank you for helping improve FootageFlow.

## Before opening a pull request

1. Open an issue for major features or architecture changes.
2. Keep provider, model, and networking logic separate from SwiftUI views.
3. Do not add analytics, tracking, advertising, hidden uploads, or paid AI dependencies.
4. Never commit API keys, credentials, personal paths, downloaded media, logs, or local databases.
5. Never guess a media license. Preserve unknown values as `UNKNOWN`.
6. Add or update English and Simplified Chinese strings together.
7. Add fixed fixtures and tests for provider parsing changes.

Run before submitting:

```bash
scripts/lint.sh
scripts/secret_scan.sh
swift build -c release
swift test
```

On a Mac without full Xcode, XCTest may be unavailable; state that clearly in the pull request and run the offline app self-test instead.

## Pull request scope

Keep changes focused. Describe user-visible behavior, test evidence, provider/API implications, privacy impact, and any platform-specific code. New macOS-only or Windows-only behavior must be isolated behind a platform interface.

By contributing, you agree that your contribution is licensed under the project's MIT License and that you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).
