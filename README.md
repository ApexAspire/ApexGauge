# ApexGauge

AI usage quotas on your wrist — an Apple Watch complication (plus iPhone companion app) showing remaining Claude, Codex, and Kimi quota at a glance.

**Status:** The app polls [status.json](https://apexaspire.github.io/ApexGauge/status.json) for endpoint-breakage notices.

One full-width rectangular complication, three rows:

```
Claude   S 42%   W 71%   F 18%
Codex    S 30%   W 55%
Kimi     W 12%
```

S = 5-hour session window, W = weekly window, F = Claude's Fable model-scoped weekly window. Values shown are **remaining** quota, refreshed every ~15–30 minutes (watchOS complication budget — real-time is not possible).

## Status

Pre-implementation. Feasibility investigation complete; build plan approved: [`docs/plan.md`](docs/plan.md).

## Architecture

- **iPhone companion app** owns all fetching and OAuth token refresh (single refresh owner — Codex refresh tokens rotate), persists a compact snapshot to the shared App Group, and pushes updates to the watch via WatchConnectivity.
- **watchOS app + WidgetKit extension** renders the cached snapshot only — no networking on the watch. `accessoryRectangular` (primary, via `AccessoryWidgetGroup`) plus `accessoryCircular` fallbacks.
- **Data sources** (same endpoints CodexBar uses; fetchers vendored from `CodexBarCore`):
  - Claude: `GET api.anthropic.com/api/oauth/usage` (OAuth token pasted once from the Mac, phone-owned refresh)
  - Codex: `GET chatgpt.com/backend-api/wham/usage` (OAuth tokens pasted once from `~/.codex/auth.json`)
  - Kimi: `GET api.kimi.com/coding/v1/usages` (official user API key from the Kimi Code Console)

## Requirements

- Paid Apple Developer Program membership (free provisioning expires every 7 days — unusable for a complication)
- Xcode on a Mac, an iPhone paired to an Apple Watch (watchOS 11+ for the 3-row `AccessoryWidgetGroup`)
- No App Store submission needed for personal use

## Connecting providers (Mac → iPhone)

To connect Claude or Codex, run the QR helper on the Mac that already has the provider signed in. Replace `codex` with `claude` when connecting Claude.

1. **Cloned repo:**

   ```sh
   swift Scripts/qr-connect.swift codex
   ```

2. **No clone, with developer tools:** clone and run — the script is inspectable before you run it.

   ```sh
   git clone --depth 1 https://github.com/ApexAspire/ApexGauge.git && cd ApexGauge && swift Scripts/qr-connect.swift codex
   ```

3. **No developer tools:** download the universal `qr-connect` binary from [GitHub Releases](https://github.com/ApexAspire/ApexGauge/releases). The binary is currently an unsigned convenience build (Developer ID signing planned) — the inspectable script above is the recommended path. Release binaries are built with [`Scripts/build-qr-connect.sh`](Scripts/build-qr-connect.sh).

The QR payload contains the refresh token (plus, for Claude, the current short-lived access token when it fits in the code; Codex may also include its non-secret account ID). The QR is rendered in a window on your Mac — nothing is written to disk — and the credentials stay in this-device-only Keychain storage on the iPhone.

## Repo layout

- `docs/plan.md` — approved build plan (phases, risks, validation)
- `Sources/ApexGaugeCore` — shared Swift package: provider fetchers (vendored from CodexBar) + cross-process snapshot model
- `App/` — iOS companion app (Xcode project, Phase 1)
- `Watch/` — watchOS app + complication extension (Phase 2–3)

## Name

Repo/product: **ApexGauge**. Naming survey (2026-08-08): `QuotaWatch` (Jira app), `TokenWatch` (multiple), `ApexPulse` (Salesforce Labs + battery monitor; also internal Pulse project) are taken; `ApexMonitor` collides with a monitor-backlight hardware product. `ApexGauge` is unclaimed, on-brand with the Apex family, and describes the UI (gauge rows). Note: [LimitWatch](https://limitwatch.app/) is an existing iPhone-widget AI-usage tracker — a direct adjacent product to be aware of if this is publicly released.

License: [MIT](LICENSE). The licence covers the code only — the "Apex Gauge" name, icon, and Apex branding are not licensed for reuse (see [NOTICE](NOTICE)); if you distribute your own build, use your own name and icon.

## Support

Best-effort support is available through [GitHub Issues](https://github.com/ApexAspire/ApexGauge/issues). There is no response-time or resolution SLA.

For private enquiries, email [admin@apexaspire.co.uk](mailto:admin@apexaspire.co.uk).
