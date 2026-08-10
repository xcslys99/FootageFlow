## What changed

Describe the user-visible behavior and the problem it solves.

## Verification

- [ ] `scripts/lint.sh`
- [ ] `scripts/secret_scan.sh`
- [ ] `swift build -c release`
- [ ] `swift test` or documented local XCTest limitation
- [ ] Relevant GUI behavior checked in the built app

## Safety and compatibility

- [ ] No API keys, personal paths, logs, databases, or downloaded media are included
- [ ] License metadata is provider-supplied; unknown values remain unknown
- [ ] English and Simplified Chinese strings are updated together
- [ ] Platform-specific behavior is isolated behind a platform adapter
- [ ] Provider quota, attribution, download, and cache rules are respected

## Screenshots

Add real screenshots for UI changes, with credentials and personal data hidden.
