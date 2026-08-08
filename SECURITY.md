# Security policy

## Supported versions

Security updates are provided for the latest released version of Apex Gauge.

## Reporting a vulnerability

Please report suspected vulnerabilities privately to **security@apexaspire.co.uk**.

**TODO — the owner must confirm this security contact email before publication.** Do not disclose a suspected vulnerability in a public GitHub issue. Include the affected version, the provider involved, steps to reproduce and the likely impact where known.

## Threat model

- Provider credentials are stored in the iPhone's this-device-only Keychain. They do not sync through iCloud or form part of a backup.
- The optional Mac helper transfers credentials optically by QR code. The QR is local to the Mac and is deleted after scanning.
- Quota data moves to the paired Apple Watch through Apple's encrypted peer-to-peer WatchConnectivity channel.
- Quota snapshots contain usage percentages and reset times, but no credentials or other secrets.

The app still relies on the security of the device, its passcode and the provider accounts connected to it. A compromised or unlocked device may expose locally available data.

## Revoking provider access

If a device, QR code or credential may have been exposed, disconnect the provider in Apex Gauge and revoke access at the provider:

- **Claude:** open Claude settings at [claude.ai](https://claude.ai), then sign out active sessions.
- **Codex / ChatGPT:** open your account at [chatgpt.com](https://chatgpt.com), then use the security controls to sign out all sessions or revoke sessions.
- **Kimi:** delete the API key in the Kimi Code Console, then create a replacement if needed.

Revocation takes effect under each provider's own security process. Reconnect Apex Gauge only after the old credential has been invalidated.

## Provider marks

Provider names and icons are used as nominative marks to identify compatible services. They remain the property of their respective owners. Apex Gauge is not affiliated with or endorsed by Anthropic, OpenAI or Moonshot.
