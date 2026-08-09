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
- **Data sources**:
  - Claude — **Mac bridge (default)**: Claude Code reports 5-hour and weekly usage to its own status line; `Scripts/apexgauge-bridge.swift` captures it there and publishes to the app's iCloud container. No Claude credentials on the phone. See [Claude bridge](#claude-bridge).
  - Claude — OAuth token (opt-in): `GET api.anthropic.com/api/oauth/usage`. Off by default and disclosed in-app; [Anthropic's Claude Code terms](https://code.claude.com/docs/en/legal-and-compliance) reserve subscription OAuth for Claude Code and Anthropic's own apps.
  - Codex: `GET chatgpt.com/backend-api/wham/usage` (OAuth tokens pasted once from `~/.codex/auth.json`)
  - Kimi: `GET api.kimi.com/coding/v1/usages` (official user API key from the Kimi Code Console)

## Claude bridge

The bridge is the default Claude path because it is the only one Anthropic's terms describe as intended: the numbers come from Claude Code itself rather than from an undocumented endpoint called with a subscription token.

```sh
./Scripts/build-apexgauge-bridge.sh
./dist/apexgauge-bridge install     # status line entry + login item
./dist/apexgauge-bridge status      # what is wired, and how fresh
./dist/apexgauge-bridge uninstall   # restores any previous status line
```

`install` writes a `statusLine` entry into `~/.claude/settings.json` and loads a `WatchPaths` LaunchAgent that republishes on change — no resident process, nothing running while Claude Code is idle. **Any status line you already use is preserved and chained**, so its output still renders.

Constraints worth knowing: figures update only while Claude Code is running, `rate_limits` is Pro/Max only and appears after the first API response of a session, and this path carries the 5-hour and weekly windows only. Both devices must be signed in to the same Apple ID with iCloud Drive enabled.

### Fable and the two capture modes

Claude Code's status line payload contains exactly two windows — verified against a live payload:

```json
"rate_limits": { "five_hour": { … }, "seven_day": { … } }
```

There are no model-scoped entries, so **Fable, Opus, and Sonnet windows cannot come from the status line**. They exist only on Anthropic's usage endpoint. The bridge therefore has two modes:

```sh
./dist/apexgauge-bridge fable off   # default — status line only, nothing contacts Anthropic
./dist/apexgauge-bridge fable on    # additionally probes the usage endpoint for Fable
./dist/apexgauge-bridge status      # shows which mode is active
```

`fable on` is opt-in and **unofficial**. It appears nowhere in Anthropic's documentation, and [Anthropic's Claude Code terms](https://code.claude.com/docs/en/legal-and-compliance) reserve subscription OAuth for Claude Code and Anthropic's own apps. Anthropic may treat it as third-party use and act on the account without notice. Use at your own risk.

Two deliberate properties when it is enabled:

- It reads the access token from the Keychain **without ever refreshing it**. Refreshing rotates the token and kills whichever copy loses the race — the reason Claude Code, CodexBar, and a phone can end up fighting over one credential lineage. An expired token simply skips the cycle.
- It probes at most once every 15 minutes, from the publish path rather than the status line, so it never runs on the render hot path.

The iPhone app needs no setting for this. It renders whatever windows the published file contains, so Fable appears when the probe is on and disappears when it is off.

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
