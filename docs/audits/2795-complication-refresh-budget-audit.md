# Audit: §2795 complication refresh budget and wake cost

**Debrief file**: `docs/debrief/2795-complication-refresh-budget-debrief.md`
**Plan file**: n/a — Roadmap §2795 is complexity 3 and has no attached build plan; its four scope bullets govern this audit.
**Repo**: ApexGauge — `github.com/apexaspire/apexgauge`
**Branch**: `feature/2795-complication-refresh-budget`
**Audit date**: 2026-10-05
**Auditing runtime/model**: Codex, `gpt-6-sol` / high (pipeline marker)
**Fixed implementation range**: `9502a5cb4b237d57012ae760ab9526b72f37f11f..07003d6cffb70ee3b026ee3902ef4ca535fadf3a`

## Findings first

### Important — I1. The committed debrief lacked fixed provenance and omitted a changed path (fixed)

The original `docs/debrief/2795-complication-refresh-budget-debrief.md:27-36` listed six paths but omitted `docs/audits/swarm-26-10-05-1.md`, which was modified in the same seven-path commit. It also lacked `Session base` and `Session end`, so `check-debrief-diff.js` stopped before it could compare the inventory. I reconstructed the debrief against the fixed parent and implementation SHAs, included the swarm record, and ran the checker: **PASS, 7 diff paths and 7 declared paths, no advisory**. This is documentation remediation only; the source behavior is unchanged.

### Important — I2. Required untethered battery comparison is unmeasured (open external acceptance)

Roadmap §2795 explicitly requires one untethered day before and one after the change. The implementation debrief and `docs/audits/swarm-26-10-05-1.md:17-18,37-38` both disclose that no physical watch measurement exists. The 30-minute policy and reload-count tests establish the requested code shape, but they do not establish a battery improvement. A true before/after comparison requires a recorded baseline on the prior revision; if none exists, the coordinator must label any future comparison as a new controlled comparison, not claim a historical before measurement. This item cannot be remediated in this worktree without a watch and elapsed device time.

### Open source findings

None confirmed in the scoped receiver. `ComplicationPayloadApplier.apply` processes the same four keys as the old receiver, preserves decode and atomic-write conditions for snapshots, and calls its injected reload closure once when any recognized value was applied. `getSnapshot(in:)` now reads only cached state; `getTimeline` retains the refresh request. The sibling watch-app receiver still reloads separately for each key in `Watch/WatchConnectivityManager.swift:137-171`; that is a distinct extension below because §2795 names the complication receiver specifically.

## 1. Plan Compliance Summary

| Roadmap §2795 scope item | Status | Evidence |
|---|---|---|
| Raise complication timeline policy to 30 minutes | implemented | `WatchComplication/ComplicationTimeline.swift:36-38,52-58`; fixed diff changes 15 to 30 minutes. |
| Collapse complication receiver reloads to one per payload | implemented | `WatchComplication/SnapshotRequester.swift:69-85`, shared applier, and six passing focused tests. |
| Stop `getSnapshot(in:)` requesting a phone refresh | implemented | `WatchComplication/ComplicationTimeline.swift:44-48`; `getTimeline` still checks freshness at lines 50-58. |
| Measure one untethered day before and after | partial | No device measurements are recorded; I2 remains open. |

**Compliance rate**: 3/4 fully implemented (75%). **Silently missing items**: none; the measurement is explicitly disclosed.

## 2. Variance Assessment

| Variance | Debrief classification | Audit assessment | Verified |
|---|---|---|---|
| Reload instrumentation through injected test closure instead of device logging | agent judgment | Tests count calls to the same closure that the complication supplies to WidgetKit; real-device budget effect remains unverified. | yes, with device limit |
| Battery measurement skipped | blocked | Correctly disclosed and still required for the full ticket outcome. | yes, open I2 |
| No Xcode project edit | agent judgment | Shared core package and complication folder use automatic file discovery; coordinator records all three compile-only target builds passing. | yes from project and coordinator record |

No undocumented source variance was found. The original debrief omitted its own fixed range and the swarm-record path; I1 repairs those provenance defects.

## 3. Code Quality Findings

- **Critical**: 0.
- **Important**: 2 total — I1 fixed in the debrief remediation; I2 open as physical-device acceptance.
- **Minor**: 0.

`prior art:` one session-knowledge lookup returned the earlier watch-to-phone request architecture and cache-only timeline pattern. They were used as path hypotheses and checked against `ComplicationTimeline.swift`, `SnapshotRequester.swift`, and `PhoneConnectivityManager.swift`; no finding rests on the prior note alone. The exact-use event was logged once under audit §2795.

## 4. Debrief Accuracy

- **Files in debrief §6 match the fixed Git diff**: yes after I1; the checker reports 7/7, with no blocking or advisory mismatch.
- **Human overrides reflected in code**: no item-specific human override was recorded; the coordinator's autonomous window is separate authority context.
- **Scope summary**: accurate against Roadmap §2795; no build plan is attached.
- **Outstanding item genuinely blocked**: yes, a physical watch and prior-version baseline are absent.
- **Gate evidence**: the debrief reports `swift test`; the committed swarm record reports 39 XCTest and 19 Swift Testing cases passing and compile-only Xcode builds for complication/watch/phone targets. Asset catalogs were excluded and no device execution was done.

**Debrief reliability**: medium for the committed original because its provenance checker was blocked; high after the audit remediation, subject to the device evidence limit.

## 5. Cleanup Items and Remediation Ledger

| ID | Severity | Item | Disposition |
|---|---|---|---|
| I1 | important | Add fixed base/end, full inventory, decision attribution and verification limits to the debrief. | Fixed in the separate audit-artifact commit; deterministic checker passes. |
| I2 | important | Obtain a real untethered battery comparison for the ticket. | Skipped in stage: requires watch, baseline and two days; coordinator owns a typed device acceptance step. |

**Cleanup counts**: 0 critical, 1 important fixed, 1 important open, 0 minor. No source-code remediation was needed.

## 6. Feature Extension Suggestions

Pipeline mode records suggestions here only; it makes no Roadmap write.

1. **Coalesce reloads in the watch-app receiver.** `Watch/WatchConnectivityManager.swift:137-171` can still call `reloadAllTimelines()` for multiple keys in one payload; a separate receiver change would extend the wake-cost reduction to the app process.
2. **Skip unchanged payload values.** Both receivers currently treat every recognized settings value as applied even if it matches persisted state; comparing before writing could avoid duplicate reloads after context redelivery.
3. **Add a bounded on-device refresh trace.** A debug-only count of timeline requests, phone wakes and reloads over a fixed untethered window would test the budget hypothesis without relying on the unit closure alone.

No promotion batch was filed in pipeline mode; the coordinator decides whether any extension merits a ticket.

## 7. Verification and Verdict

**Validation run**: `swift test --disable-sandbox --filter ComplicationPayloadApplierTests` passed 6/6 after compiling the shared core; `check-debrief-diff.js` passed 7/7; `git diff --check` passed. The initial local `swift test` attempt failed at SwiftPM's nested sandbox setup (`sandbox_apply: Operation not permitted`); a corrected full-suite run built but did not finish within the audit window and was interrupted, so this auditor does not claim a full-suite pass. The coordinator's committed gate record reports a full suite pass (39 XCTest and 19 Swift Testing) plus three compile-only device-SDK target builds. A local `xcodebuild -list` attempt was blocked by this sandbox's Xcode cache and simulator access; it is not an app failure. No device install, live WidgetKit reload count or battery comparison was performed.

**Resource footprint**: the requested timeline interval falls from 15 to 30 minutes, a nominal reduction from 96 to 48 timeline requests/day before watchOS scheduling discretion. A stale timeline may still ask the phone to run up to three provider fetches through `UsageEngine.refreshAll`, while phone-initiated pushes are separate. The applier reduces one received payload from up to four reload requests to at most one; it adds no database read or external call. Device wake and battery savings remain unmeasured.

**Overall assessment**: **concerns**. The three scoped source edits and focused tests are sound, and I1 is repaired. The fourth ticket requirement is still unverified on a physical watch; this audit cannot support a claim that battery cost improved or that §2795 is fully accepted. The coordinator should retain the source branch and the explicit measurement boundary until it resolves I2.

**Roadmap disposition**: no write by the pipeline auditor; audit-state and device-step decisions belong to the coordinator.
**Commit disposition**: debrief repair and paired audit artifacts committed separately from implementation; no push, merge or rebase by the auditor.
**Runtime asymmetry**: Codex used the local Apex Developer Tools Roadmap/Knowledge readers, wrote no Roadmap state in pipeline mode, and returns its result through the atomic stage marker with a best-effort tmux wake.

## Confirmation

Audit: `docs/audits/2795-complication-refresh-budget-audit.md`
Cleanup: `docs/audits/2795-complication-refresh-budget-cleanup.md`
Counts: 0 critical; 1 important fixed; 1 important open; 0 minor
Promotions: three suggestions in report only; no pipeline Roadmap write
