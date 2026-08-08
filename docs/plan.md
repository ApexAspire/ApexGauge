# Plan: AI-usage Apple Watch complication (Claude / Codex / Kimi)

## Feasibility verdict

**Feasible.** All three providers expose their quota data as small bearer-token HTTPS JSON calls (the exact calls CodexBar makes), the watch can render them via a WidgetKit `accessoryRectangular` complication (the full-width "next meeting" slot the user described), and a realistic refresh cadence of ~15–30 min is achievable — fine for quota data. The only genuinely hard part is credential lifecycle for Claude and Codex (details below); Kimi is clean.

## Investigation findings (evidence base)

### Data sources (from `/Users/petersmini/Projects/CodexBar` source + web research)

| Provider | Endpoint | Auth | Notes |
|---|---|---|---|
| Claude | `GET https://api.anthropic.com/api/oauth/usage` | Bearer OAuth token + `anthropic-beta: oauth-2025-04-20` header + `claude-code/*` UA | Returns `five_hour`, `seven_day`, `seven_day_sonnet/opus`, and `limits[]` incl. the **Fable** model-scoped weekly window (`ClaudeUsageFetcher.swift:1090-1108`). S/W/F = **Session (5h) / Weekly (7d) / Fable** — confirmed. No official subscription-quota API exists (Admin API is API-billing only). Undocumented; rate-limited; grey-zone but no known enforcement against read-only polling. Refresh: `POST platform.claude.com/v1/oauth/token`, public client_id `9d1c250a-…`; works from mobile IPs, risky from datacenter IPs (Cloudflare WAF). |
| Codex | `GET https://chatgpt.com/backend-api/wham/usage` | Bearer token + `ChatGPT-Account-Id` header | Returns `rate_limit.primary_window` (5h) / `secondary_window` (weekly) + credits. Internal/undocumented. Refresh: `POST auth.openai.com/oauth/token`, public client_id `app_EMoamEEZ73…`. **Hazard: refresh tokens rotate** — if the phone refreshes, the Mac's `~/.codex/auth.json` lineage goes stale and the Codex CLI can break (`refresh_token_reused`). Refresh must have exactly one owner. |
| Kimi | `GET https://api.kimi.com/coding/v1/usages` | Bearer API key | Official user-created API key from the Kimi Code Console (up to 5 keys). Returns weekly quota + 5h rate-limit window. Works from any IP, no cookies/OAuth/rotation. Cleanest of the three. |

### watchOS mechanics (Apple docs / WWDC)

- Complications are WidgetKit "accessory" widgets. **`accessoryRectangular`** is the full-width style requested; watchOS 11+ `AccessoryWidgetGroup` allows up to 3 labelled rows in one rectangular widget — ideal for one row per provider. Supporting `accessoryCircular`/`accessoryCorner`/`accessoryInline` as fallbacks maximizes watch-face coverage (user's 3× circular idea also possible as a secondary widget).
- The watch app can make **arbitrary HTTPS calls itself** via `URLSession` (proxied through iPhone, or direct Wi-Fi/cellular) — no iPhone companion strictly required. Background-refresh budget with an active-face complication: ~4 background tasks/hour and ~40–70 timeline reloads/day → **~15–30 min update cadence**, never real-time.
- Alternative data path: iPhone companion fetches, pushes via WatchConnectivity (`transferCurrentComplicationUserInfo` = 50 pushes/day budget; `updateApplicationContext` unlimited, delivered on wake).
- Distribution: free Apple ID = provisioning expires every 7 days (unusable for this). **Paid Apple Developer Program ($99/yr) required** for it to run indefinitely; no App Store submission needed.

## Architecture (recommended)

**iPhone companion app + watchOS app with WidgetKit complication extension.**

- The **iPhone app owns all fetching and token refresh** (single refresh owner — contains the Codex rotation hazard), persists a compact snapshot to the shared App Group, and pushes updates to the watch via WatchConnectivity.
- The **watch complication renders the cached snapshot only** — no networking on the watch itself (preserves complication budget, avoids duplicating token logic). `WCSessionDelegate` on the watch receives transfers and calls `WidgetCenter.shared.reloadTimelines(ofKind:)`.
- iPhone refresh loop: `BGAppRefreshTask` every ~15–30 min + fetch on app open + push to watch when values changed. Mirrors CodexBar's existing WidgetSnapshot pattern (it already persists a snapshot JSON to an App Group and reloads its macOS widget every 30 min).
- **Why not watch-direct fetch:** burns complication/background budget on networking, and duplicates OAuth refresh logic in the least-debuggable target. Why not Mac relay: data goes stale whenever the Mac sleeps — bad for a glanceable watch.

### Credential onboarding (one-time, in the iPhone app)

- **Kimi:** user creates an API key in the Kimi Code Console and pastes it. Done.
- **Claude:** user pastes the refresh token from `~/.claude/.credentials.json` (guided: app shows exact `jq`/`security` command to extract it on the Mac). iPhone app then owns refresh against `platform.claude.com/v1/oauth/token`. Polling ≥5 min to respect the aggressive rate limits; honor `Retry-After`.
- **Codex:** user pastes `access_token` + `refresh_token` + `account_id` from `~/.codex/auth.json`. iPhone app owns refresh. **Documented caveat:** if the Mac's Codex CLI later refreshes independently, the phone's lineage dies → app must surface "re-paste token" recovery UX. (Phase-3 option below removes this.)

### Complication UI

- Primary: `accessoryRectangular` using `AccessoryWidgetGroup` with 3 rows:
  - `Claude  S 42%  W 71%  F 18%` (S=Session 5h, W=Weekly, F=Fable weekly-scoped)
  - `Codex   S 30%  W 55%`
  - `Kimi    W 12%` (+ 5h rate window when present)
  - Remaining-percent display (100 − used) with a small gauge per row; stale indicator ("as of HH:MM") when snapshot age > ~45 min.
- Secondary widget: `accessoryCircular` per-provider ring (user's 3× circular option) — trivial once the snapshot pipeline exists.
- `privacySensitive` on the widget content (visible on Always-On display).

## Code reuse

Vendor from CodexBar's `CodexBarCore` target (Foundation-only, already Linux-portable, no macOS dependencies in these files) into the new app's shared framework:
- `Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift` + models + rate-limit gate
- `Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift` + `CodexTokenRefresher.swift` + models
- `Providers/Kimi/KimiUsageFetcher.swift` (`fetchCodeAPIUsage` path only) + `KimiModels.swift`
- `WidgetSnapshot.swift` / `RateWindow` models as the cross-process snapshot format

Do **not** port: SweetCookieKit, WebKit fallbacks, keychain/file credential readers (replaced by the app's own onboarding + iOS Keychain storage).

## Project location

New repo `~/Projects/usage-watch/` (Xcode project, three targets: iOS app, watchOS app, watch WidgetKit extension; shared Swift package for vendored fetchers + snapshot model). Kept separate from the CodexBar checkout, which is steipete's upstream project and macOS-only.

## Build phases

1. **Phase 1 — iPhone fetch engine + settings UI.** Xcode project skeleton; vendor fetchers; Keychain storage for the three credentials; onboarding screens with per-provider paste instructions + Mac extraction commands; foreground fetch + snapshot persistence to App Group; display current values in the iOS app itself (this alone is debuggable end-to-end before any watch work). Verify: values match CodexBar's menu-bar numbers within one refresh cycle.
2. **Phase 2 — Background refresh + watch pipeline.** `BGAppRefreshTask` scheduling (~15–30 min), change-detection, WatchConnectivity `transferCurrentComplicationUserInfo` (primary) + `updateApplicationContext` (fallback), watch-side `WCSessionDelegate` + snapshot store.
3. **Phase 3 — Complication.** `accessoryRectangular` with `AccessoryWidgetGroup` (Claude S/W/F, Codex S/W, Kimi W) + circular fallbacks; timeline provider rendering cached snapshots; stale-data rendering; on-wrist verification of refresh cadence over a full day.
4. **Phase 4 (optional) — Codex rotation fix + polish.** If Codex token re-pastes prove annoying: add a small Mac-side helper (or CodexBar patch) that writes rotated tokens to iCloud Keychain/CloudKit so the phone re-syncs instead of breaking. Error banners, retry/backoff polish, reset-time display.

## Risks & mitigations

- **Codex refresh-token rotation** breaking the Mac CLI lineage → phone is sole refresh owner; in-app "re-paste" recovery flow; Phase-4 sync helper if needed.
- **Claude endpoint brittleness** (undocumented, 429s, UA filtering) → ≥5-min poll floor, honor `Retry-After`, surface fetch errors in the iOS app rather than failing silently on the watch face.
- **Endpoint shape changes** (all three unofficial to some degree) → isolate each fetcher behind the vendored CodexBar modules so upstream CodexBar fixes can be re-vendored.
- **Stale data on wrist** → every complication entry carries its timestamp; render "as of" and dim when stale.
- **Paid developer account required** — assumed already held (per project portfolio); confirm before Phase 1.

## Validation

- Phase 1: side-by-side numbers vs CodexBar for all three providers; Claude S/W/F buckets match menu-bar labels; token refresh survives >24h without re-paste.
- Phase 3: complication updates every 15–30 min across a day with the face active; correct rendering in Always-On dimmed state; stale indicator appears when iPhone is offline.
