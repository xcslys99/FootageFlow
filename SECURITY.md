# Security policy

## Supported versions

Security fixes are provided for the latest published FootageFlow release.

FootageFlow v0.5.0 supports macOS 15+ on Apple Silicon and Windows 11 x64.

## Reporting a vulnerability

Please do not open a public issue for a credential leak, unsafe file operation, remote-code-execution risk, or another vulnerability that could harm users. Use the repository's private **Security → Report a vulnerability** form. Include affected version, reproduction steps, impact, and any suggested mitigation.

Do not include real API keys, private media, or personal file paths. Replace them with safe placeholders.

## Security boundaries

- API keys are stored through the operating system's secure credential store.
- Only HTTPS provider URLs without embedded credentials are accepted.
- Logs redact authorization, cookie, password, token, and API-key patterns.
- FootageFlow does not execute downloaded media, shell commands, or provider-supplied scripts.
- App-initiated local deletion is restricted to the configured download root and requires explicit confirmation.
- The repository's secret scan is a safety net, not a substitute for review.

The v0.5.0 macOS build is Ad Hoc signed and not notarized. The v0.5.0 Windows installer is not code-signed. These are distribution limitations, not claims of Apple or Microsoft verification. Release assets include SHA-256 checksums for independent verification.
