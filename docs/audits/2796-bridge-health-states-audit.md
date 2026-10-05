# Audit: §2796 bridge health states

**Debrief file**: `docs/debrief/2796-bridge-health-states-debrief.md`
**Plan file**: n/a — Roadmap §2796 is complexity 3, has no attached plan, and supplies the governing scope
**Repo**: ApexGauge — `github.com/apexaspire/apexgauge`
**Branch**: `feature/2796-bridge-health-states`
**Audit date**: 2026-10-05
**Auditing runtime/model**: Codex, `gpt-6-sol` / high (pipeline stage marker)
**Fixed implementation range**: `2f9c68004937bc9f8020c287470de9db1caaea1b..1520bed78d7b093663d2120044f512dd9193f45a`
**Remediation commit**: `1c28e4f4f205ff5c30d9528bf234d70c5d033bd0`

## Findings first

### Important — I1. Scheduled and watch-request refreshes discarded last-known bridge figures (fixed)

`App/ApexGaugeApp.swift:42-53` had a second refresh pipeline that saved the empty state snapshot directly. The new `UsageViewModel` carry-forward rule covered foreground refreshes only. A scheduled refresh during a transient iCloud outage therefore erased the previous figures; an explicit watch request returned the empty snapshot. The remediation loads the prior persisted snapshot and applies the same merge rule before saving, returning, or pushing it.

### Important — I2. State-only changes did not trigger a watch push (fixed)

`App/Infrastructure/SnapshotChangeDetector.swift:53-69` previously compared only quota-window keys and percentages. Since carry-forward deliberately preserves windows, bridge state transitions could wait for the 30-minute push-age limit even though `Watch/ContentView.swift:15-20` renders the state. The remediation compares each provider's `bridgeState` before quota values, so a refresh can push a state transition immediately. This does not bypass the existing transport success and complication-budget checks.

### Important — I3. Carry-forward could present mock or OAuth figures as bridge measurements (fixed)

`Sources/ApexGaugeCore/Snapshot.swift:111-119` formerly accepted any prior Claude windows. Switching from mock or OAuth mode to an unavailable bridge could retain unrelated figures under a bridge health banner. The remediation requires a prior `capturedAt`, which bridge measurements carry and mock/OAuth snapshots do not. `Tests/ApexGaugeCoreTests/ClaudeBridgeFetcherTests.swift:245-250` covers this boundary.

### Open findings

None. The three important findings above were remediated within 33 changed lines, below the 2× audited-diff limit. No critical or minor code finding was retained.

## 1. Plan Compliance Summary

| Roadmap §2796 scope item | Status | Evidence |
|---|---|---|
| Model bridge states explicitly | implemented | `ClaudeBridgeReading`, `ClaudeBridgeState`, and `ProviderSnapshot.bridgeState`; focused tests pass. |
| Surface actionable state on the Claude dashboard card | implemented | `ProviderCardView` renders `BridgeStateBannerView` and shared detail copy. |
| Distinguish watch bridge idle from waiting for iPhone | implemented | `Watch/ContentView` renders `watchText` when a phone snapshot exists; transport now pushes state changes. |
| Cover Pro/Max-only absence of `rate_limits` | partial | The `.noCapture` copy names this possibility. The helper writes no capture when `rate_limits` is absent, so the phone cannot distinguish plan-unmet from helper-not-installed or idle. Existing follow-up §4811 proposes a helper status signal. |

**Compliance rate**: 3/4 fully implemented (75%); one documented protocol-limited item is partial. **Silently missing items**: none.

## 2. Variance Assessment

| Variance | Debrief classification | Audit assessment | Verified |
|---|---|---|---|
| Preserve prior windows when bridge becomes unavailable | Review fix | Correct for foreground refresh; scheduled/watch-request path was omitted and remediated as I1. | reclassified |
| Leave complication UI unchanged | Documented | Its cached snapshot still contains windows; state-driven transport changes are required for the watch app. | yes |
| Share Settings/card read logic | Claimed | Both call `ClaudeBridgeFetcher.read()`; they can still differ temporarily because Settings reads independently and the card reads a cached refresh. | qualified |
| State-only watch transport | Undocumented | Missing change-detector comparison was remediated as I2. | undocumented |

The Pro/Max limit is accurately disclosed in the debrief and swarm record. No project-file edit was required for these existing Swift files.

## 3. Code Quality Findings

- **Critical**: 0.
- **Important**: 3, all fixed by `1c28e4f` (I1–I3 above).
- **Minor**: 0.

`prior art:` one session-knowledge lookup found the ApexGauge App Group snapshot and measured-versus-fetched timestamp contracts; both matched the code review. Its exact-use event was recorded once under audit §2796.

## 4. Debrief Accuracy

- **Files in debrief §6 match the fixed Git diff**: no. The seven implementation Swift paths match, but committed `docs/audits/swarm-26-10-05-1.md` is omitted because §6 copied pre-commit `git status`; the debrief itself is also included in the commit.
- **Human overrides in §3a reflected in code**: no §3a or human override was declared; none was needed for this scope.
- **Plan summary accurately describes scope**: yes, against Roadmap §2796; no build plan was attached.
- **Outstanding items genuinely blocked**: yes for on-device rendering/WatchConnectivity; §4811 already covers the helper protocol gap.
- **Gate evidence**: the debrief lists focused Swift tests and parse checks. The committed swarm record additionally reports `swift test` and iPhone/watch source builds. The audit independently reran these checks after remediation.

**Debrief reliability**: medium — the source inventory and foreground behavior are accurate, but the shared refresh path and transport change filter were omitted from the review narrative.

## 5. Cleanup Items and Remediation Ledger

| ID | Severity | Item | Disposition |
|---|---|---|---|
| I1 | important | Apply carry-forward in the scheduled/watch-request pipeline. | Fixed in `1c28e4f`; iPhone target compiled. |
| I2 | important | Include bridge-state changes in watch push decisions. | Fixed in `1c28e4f`; iPhone/watch targets compiled. Device transfer unverified. |
| I3 | important | Carry forward only genuine bridge measurements. | Fixed in `1c28e4f`; focused regression test passed. |

**Cleanup counts**: 0 critical, 3 important fixed, 0 important outstanding, 0 minor.

## 6. Feature Extension Suggestions

Pipeline mode records suggestions here only; it does not write Roadmap state.

1. **Publish a Mac-helper status/reason signal** (already filed as §4811). Distinguishes plan-unmet, helper-uninstalled and idle without asking the phone to guess from a missing file.
2. **Expose iCloud download-pending separately from no capture.** An evicted cloud file may exist as a metadata stub; a pending state would give the user a correct wait/retry instruction.
3. **Add an in-app bridge setup check.** A short diagnostic could verify iCloud container access, last capture time and paired Apple ID setup before users troubleshoot quota values.

No promotion batch was filed in pipeline mode; suggestion 1 already has a Roadmap ticket.

## 7. Verification and Verdict

**Validation run**: `swift test` passed (33 XCTest and 19 Swift Testing cases); iPhone `ApexGauge` and watch `ApexGaugeWatch` device-SDK targets compiled with signing and asset catalogs excluded; `git diff --check` passed. The initial sandboxed test/build attempts failed before compilation on denied Swift/Xcode cache and simulator access; the same checks passed with ordinary Xcode access. The source build reports an existing non-Sendable `SnapshotChangeDetector` capture warning. No device install, UI rendering, asset-catalog compilation, dynamic-type check, or WatchConnectivity transfer was run.

**Resource footprint**: remediation adds one local App Group JSON read per scheduled/watch refresh (roughly every 15 minutes, at most about 96 normal scheduled reads/day, snapshot-sized). It adds no provider API call and no database access; state changes may cause an additional budgeted watch push.

**Overall assessment**: **acceptable**. The three verified implementation gaps are fixed and source/test gates pass. The Pro/Max distinction remains a known helper-protocol limit, with follow-up §4811. Device presentation and transfer remain unverified acceptance surfaces for the coordinator.

**Roadmap disposition**: no write from pipeline auditor; coordinator owns audit-state update and §4811 follow-up.
**Commit disposition**: remediation `1c28e4f`; this report and paired cleanup plan committed separately; no push, merge or rebase by auditor.
**Runtime asymmetry**: Codex used the local `mcp__apex_developer_tools` knowledge/Roadmap readers, wrote no Roadmap state in pipeline mode, and returns the stage through its atomic marker plus a best-effort tmux wake.

## Confirmation

Audit: `docs/audits/2796-bridge-health-states-audit.md`
Cleanup: `docs/audits/2796-bridge-health-states-cleanup.md`
Counts: 0 critical; 3 important fixed; 0 important open; 0 minor
Promotions: three suggestions in report only; no pipeline Roadmap write
