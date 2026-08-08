# Debrief: plan

**Plan file**: [`docs/plan.md`](docs/plan.md)
**Repos involved**:
- `ApexGauge` — `https://github.com/ApexAspire/ApexGauge.git` (primary)
- `agent-dotfiles` — `git@github.com:ApexAspire/apex-agent-dotfiles.git` (slug-registry entry only; committed by a concurrent session, 206cd1f)

**Date**: 2026-08-08
**Agent model**: kimi k2.7 (coordinator) + gpt-5.6-sol high/xhigh (Codex tmux workers)
**Session duration**: ~8 hours

---

## 1. Plan Summary

Investigate whether CodexBar's three usage monitors (Claude, Codex, Kimi) could become an Apple Watch complication showing quota remaining, and if feasible build it. The plan proposed an iPhone companion app owning all fetches and OAuth refresh, a watchOS app + WidgetKit complication rendering cached snapshots pushed over WatchConnectivity, and four phases (fetch engine → sync pipeline → complication → optional token-sync helper). The session then continued past the plan into live-test fixes, UI design passes, App Store preparation, security review remediation, and open-source publication.

## 2. Implementation Log

- **Item**: Feasibility investigation (3 parallel explore agents: CodexBar source, watchOS mechanics, provider auth) + approved plan
- **Plan reference**: pre-plan requirement
- **Files touched**: `docs/plan.md`
- **Commit**: `1d91dcb`

- **Item**: Phase 1 — coordinator-owned API contract, then 2 parallel Codex workers (core fetchers vendored from CodexBar + iOS app/Xcode project); coordinator wired live engine
- **Plan reference**: Phase 1
- **Files touched**: `Sources/ApexGaugeCore/**`, `Tests/**`, `App/**`, `ApexGauge.xcodeproj/**`
- **Commit**: `97bf273`, `88b0201`, `a5cd690`, `f6e5d5a`

- **Item**: Phase 2 — BGAppRefreshTask scheduler, WatchConnectivity push with change detection, watchOS app target + receiver + proof UI
- **Plan reference**: Phase 2
- **Files touched**: `App/Background/**`, `App/Connectivity/**`, `App/Infrastructure/SnapshotChangeDetector.swift`, `App/Info.plist`, `Watch/**`
- **Commit**: `56a1cb0`, `3bd4b58`, `d80b6ae`, `557c5ce`

- **Item**: Phase 3 — WidgetKit complication extension (rectangular group + circular)
- **Plan reference**: Phase 3
- **Files touched**: `WatchComplication/**`, project file
- **Commit**: `b32380f`, `fe892fe`

- **Item**: QR onboarding (optical credential transfer), paste-anything parser, % used/left toggle with watch propagation, secret-transit hardening
- **Plan reference**: unplanned (live-feedback ticket §2713)
- **Files touched**: `Sources/ApexGaugeCore/CredentialsParser.swift`, `App/Views/Settings/**`, `WatchComplication/**`, `Scripts/qr-connect.swift`
- **Commit**: `0890c2e`, `7282b89`, `cea4250`, `d77c9ab`, `de24b68`

- **Item**: Bundle-ID migration to `com.apexaspire.apexgauge.*` (portal collision), complication ID `.watch.widgets`, app icon wiring, qr-connect distribution plumbing
- **Plan reference**: unplanned (provisioning failure on device)
- **Files touched**: project file, entitlements, `App/Info.plist`, asset catalogs, `Scripts/build-qr-connect.sh`, `docs/distribution.md`, README
- **Commit**: `ad92d29`, `56c4a75`, `cfa5c83`, `8efaceb`

- **Item**: qr-connect Keychain-first Claude credentials (live store vs months-stale file)
- **Plan reference**: unplanned (live bug)
- **Commit**: `87e44f4`

- **Item**: Live-test fixes (§2721) — Codex window classification by `limit_window_seconds`, Claude QR carries access token, Session/Week/Fable labels, reset countdown toggle, per-provider refresh
- **Commit**: `5e88f89`, `783f519`

- **Item**: Apex design system pass (§2722) + density/layout corrections
- **Commit**: `0f3fc77`, `985e5df`, `17894b3`, `4416da1`

- **Item**: Watch data delivery (§2724) — push-gate/record-before-send bugs fixed by coordinator; watch-initiated refresh (request→wake→reply→reload) by worker
- **Commit**: `4b702b2`, `7e48e83`

- **Item**: Complication "Please adopt container" fix (`.containerBackground`), watch app UI rework (thin gauges, full labels, reset countdowns)
- **Commit**: in `9xxx`–`4416da1` range (Watch/ContentView + ComplicationViews commits)

- **Item**: Complication redesign v2/v3 — half-width Session+chosen bars, per-provider show/hide, CodexBar brand icons via shared catalog, text sizing iterations
- **Commit**: `8a7da84`, `fa2c766`, `303ffac`, `4416da1`

- **Item**: App Store prep (§2730) — flattened no-alpha icon, export-compliance key, privacy policy, review notes, metadata sheet, submission guide, screenshots, universal qr-connect binary, credential audit
- **Commit**: `e4b3471`, `8070c88`

- **Item**: MIT LICENSE + NOTICE (brand carved out), release canvassing (sol + opus, unanimous free+MIT)
- **Commit**: `c0f933a`, `dc6b307` + README commits

- **Item**: Security review (sol xhigh, SAFE WITH FIXES) + full remediation (clone-first instructions, mock-mode honoured everywhere, accurate Keychain claims, payload disclosure, no raw error bodies, in-memory QR window, gitignore hardening)
- **Commit**: `2deded3`, `787fb29`, `6b42f4f` et al.

- **Item**: Publication — public repo, GitHub Pages (privacy policy + status.json), provider-status banner feature, SECURITY.md/support docs
- **Commit**: through `96825ee`

## 3. Decisions Register

- **Decision**: iPhone-companion architecture over watch-direct fetch or Mac relay
- **Made by**: agent (plan), ratified by human
- **Rationale**: single refresh owner contains Codex rotation; Mac relay goes stale when asleep
- **Alternatives considered**: watch-direct URLSession; Mac relay via iCloud
- **Plan impact**: none (was the plan)

- **Decision**: name ApexGauge
- **Made by**: agent
- **Rationale**: naming survey — QuotaWatch/TokenWatch/ApexPulse/ApexMonitor taken or colliding
- **Alternatives considered**: ApexMonitor, QuotaWatch
- **Plan impact**: repo name changed from plan's usage-watch placeholder

- **Decision**: phone as sole OAuth refresh owner; §2708 sync helper deferred
- **Made by**: human+agent
- **Rationale**: rotation hazard; defer until re-paste cadence proves painful
- **Plan impact**: Phase 4 parked in `later`

- **Decision**: QR optical transfer as primary onboarding; paste fallback with caveat
- **Made by**: human (security constraint) + agent (design)
- **Rationale**: no typing on phone; no iCloud/pasteboard transit for secrets
- **Plan impact**: replaced plan's paste-only onboarding

- **Decision**: free + MIT release, brand carved out via NOTICE
- **Made by**: human (after canvassing sol + opus, unanimous)
- **Rationale**: no pricing power against free CodexBar; endpoint-breakage support risk; credentials trust requires inspectable source
- **Alternatives considered**: paid, freemium, BUSL, closed-source

- **Decision**: security-review findings all remediated pre-publication
- **Made by**: agent, no objection
- **Rationale**: high finding (curl-and-run + quarantine-strip guidance) was a genuine credential-theft path

### 3a. Human Overrides

- "kimi is better than codex at UI — amend/improve what codex does" → later UI fixes done directly by kimi coordinator.
- "use the ones from codexbar" for provider icons (replacing SF Symbols).
- Security constraint: no iCloud-class transit for credentials (drove QR design).
- % used as default display mode (over agent's % left default).
- Codex classification concern ("weekly due to reset soon would misclassify") — verified the implementation used window duration, not reset proximity; no change needed.

## 4. Variances

- **Plan item**: onboarding by pasting individual tokens with jq extraction commands
- **What actually happened**: QR optical transfer + paste-anything parser
- **Reason**: typing long commands on a phone infeasible; jq interpolation displayed literally (bug)
- **Classification**: human_decision + technical_constraint

- **Plan item**: complication uses `AccessoryWidgetGroup` with header row
- **What actually happened**: plain VStack rows, no header; later half-width Session+chosen mini-bars
- **Reason**: space premium; three windows per provider unreadable at complication scale
- **Classification**: human_decision (iterative on-wrist feedback)

- **Plan item**: `com.apex.apexgauge.*` bundle IDs
- **What actually happened**: `com.apexaspire.apexgauge[.watch[.widgets]]`
- **Reason**: portal registration collisions with another team
- **Classification**: technical_constraint

- **Plan item**: watch renders cached snapshots pushed by phone only
- **What actually happened**: added watch-initiated refresh (watch requests, phone wakes and replies)
- **Reason**: requirement "complication updates without opening the iPhone app"; BGAppRefresh alone unreliable
- **Classification**: human_decision

## 5. Outstanding Items

- **Item**: §2708 Phase 4 Codex/Claude token sync helper
- **Reason not completed**: optional; deferred until rotation re-paste cadence proves painful
- **Recommended next step**: re-scan QR when Codex shows unauthorized; if frequent, build the iCloud Keychain/CloudKit token-writeback helper
- **Priority**: optional

- **Item**: App Store submission (owner actions in `docs/app-store/submission-guide.md`)
- **Reason not completed**: requires owner's App Store Connect account + 2 device screenshots + review recording
- **Recommended next step**: follow the guide; archive can be run by the agent on request
- **Priority**: important

- **Item**: Developer ID signing/notarization of qr-connect binary
- **Reason not completed**: no Developer ID certificate on the build machine
- **Recommended next step**: create cert in Xcode account settings, sign, notarize, update release
- **Priority**: low (script path is primary)

## 6. Files Changed

**Session base**: `1d91dcb` (root commit — the repo was created in this session; resolved via user-supplied session context)
**Session end**: `96825ee` (captured immediately before writing this debrief)
**Diff command**: `git diff --stat 1d91dcb..96825ee` (91 files, +7366/−3; the root commit itself added README, .gitignore, Package.swift, initial Snapshot.swift + test)

### Created
- `Sources/ApexGaugeCore/**` — Contract, Snapshot model, CredentialsParser, ConnectPayload, ProviderStatus, fetchers (Claude/Codex/Kimi), UsageEngine, HTTPClient
- `Tests/ApexGaugeCoreTests/**` — 33 tests
- `App/**` — iOS app (dashboard, onboarding, settings, connectivity, background refresh, theme)
- `Watch/**` — watchOS app (receiver, store, list UI)
- `WatchComplication/**` — WidgetKit extension (rectangular + circular)
- `Shared/Assets.xcassets/**` — vendored provider icons
- `Scripts/qr-connect.swift`, `Scripts/build-qr-connect.sh`
- `ApexGauge.xcodeproj/**` — hand-authored synchronized-folder project
- `docs/**` — plan, distribution, app-store pack (privacy/review/metadata/guide), security review, status.json
- `LICENSE`, `NOTICE`, `SECURITY.md`, `Design/**`

### Modified
- README.md — architecture, distribution, license/trademark notes

### Deleted
- None (excluding superseded root-level icon PNGs moved into `Design/`)

## 7. Risks and Caveats

- Claude + Codex endpoints unofficial; breakage expected eventually — status.json banner is the mitigation; Kimi official.
- Token rotation: phone is refresh owner; Mac CLI lineages can stale (self-heals by CLI re-auth; watch for user friction → §2708).
- Complication refresh cadence (~15–60 min) not yet soak-verified across a full day on the active face.
- Notarization pending for the helper binary; unsigned binary offered only as optional convenience.
- Watch app was installed via devicectl; the iOS Watch-app install path was never re-verified after the stale-state cleared.

## 8. Audit Checklist

- [x] Every plan item has a corresponding entry in §2 or §5
- [x] Every variance in §4 has a rationale
- [x] Every human override in §3a is documented with context
- [x] Files listed in §6 match the git diff for this session
- [x] No plan items are silently missing

---

## Audit handoff

To audit this debrief in a fresh agent session, run:

```text
/audit ApexGauge/docs/debrief/plan-debrief.md
```
