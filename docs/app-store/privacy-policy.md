# Apex Gauge — Privacy Policy

**Effective date: 8 August 2026**
**Publisher: Apex Aspire Limited** ([TODO: registered office address])

## Summary

Apex Gauge collects nothing. No analytics, no tracking, no accounts, no crash
reporting, no advertising identifiers. There is no Apex Gauge server.

## What the app stores

- **Provider credentials** (Claude OAuth tokens, Codex/ChatGPT OAuth tokens,
  Kimi API key) that you supply during setup. These are stored only in the
  iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: they
  never leave the device, are excluded from iCloud Keychain sync, and do not
  migrate to a new device.
- **Quota snapshots** (usage percentages and reset times), stored in the
  on-device App Group container shared with the Apple Watch companion app.
  Snapshots contain no credentials.

## What leaves the device

The app contacts only the three provider APIs (api.anthropic.com,
chatgpt.com, api.kimi.com) to fetch your usage quotas, plus the providers'
OAuth token endpoints to refresh credentials. These requests go directly from
your device to the provider over HTTPS and are governed by the provider's own
privacy policy. Usage data is transferred to your paired Apple Watch over
Apple's encrypted WatchConnectivity channel only.

## The optional Mac companion script (qr-connect)

The qr-connect helper renders a QR code in a window on your Mac so the app
can receive credentials optically. It reads your local CLI credential files,
keeps the payload in memory, and writes nothing to disk. It makes no network
requests.

## Data retention and deletion

All data lives on your devices. Disconnecting a provider in Settings deletes
its credentials immediately — do this before uninstalling if you want them
gone, because iOS can retain an app's Keychain items after deletion.
Snapshots are removed with the app.

## Changes

Any change to this policy will be published at [TODO: privacy URL] before it
takes effect.

## Contact

[TODO: privacy contact email — e.g. privacy@apexaspire.co.uk]
