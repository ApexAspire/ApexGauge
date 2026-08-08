# QR Connect Distribution

Release checklist for the macOS QR helper:

1. Run `Scripts/build-qr-connect.sh` from the repository root. It compiles macOS 13 arm64 and x86_64 executables, then combines them into `dist/qr-connect`.
2. Confirm `dist/qr-connect --selftest` prints `SELFTEST OK`, and confirm running it without arguments prints usage and exits non-zero.
3. Sign the universal binary with the ApexGauge Developer ID certificate and verify the signature. If signing changes the binary after the build script runs, generate the published `shasum -a 256 dist/qr-connect` again.
4. Attach the signed `qr-connect` binary and its final SHA-256 checksum to the matching [GitHub release](https://github.com/ApexAspire/ApexGauge/releases).

## Future

- Explore upstream integration with CodexBar.
- Publish a Homebrew tap for installation and upgrades.
