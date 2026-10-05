# Cleanup Plan: §2796 bridge health states

**Source**: `docs/audits/2796-bridge-health-states-audit.md`
**Generated**: 2026-10-05
**Governing scope**: Roadmap §2796, complexity 3, no attached build plan
**Base/end**: `2f9c68004937bc9f8020c287470de9db1caaea1b..1520bed78d7b093663d2120044f512dd9193f45a`
**Total items**: 3 (0 critical, 3 important, 0 minor); all remediated in `1c28e4f4f205ff5c30d9528bf234d70c5d033bd0`

## Critical

None.

## Important

### I1. Preserve last-known bridge figures in every refresh pipeline — fixed

- **What**: Scheduled and explicit watch-request refreshes saved a fresh empty bridge-state snapshot without the foreground carry-forward rule.
- **Where**: `App/ApexGaugeApp.swift` shared `performRefresh` closure.
- **Why**: A transient iCloud outage erased prior Claude figures and removed the watch's last-known context.
- **How**: Load the prior App Group snapshot, apply `ProviderSnapshot.carryingForward(from:)` to each refreshed provider before saving, returning, or pushing. Implemented at `App/ApexGaugeApp.swift:44-53`.
- **Evidence**: iPhone target compile passed; the same merge rule is covered by core tests. Device transfer remains unverified.

### I2. Push bridge-state transitions to the watch — fixed

- **What**: The push detector checked only quota windows, so a state change with preserved percentages was invisible until its 30-minute age threshold.
- **Where**: `App/Infrastructure/SnapshotChangeDetector.swift`.
- **Why**: The watch could continue to show healthy Claude figures while the phone knew that the bridge was unavailable.
- **How**: Compare each provider's old and new `bridgeState` before quota values. Implemented at `App/Infrastructure/SnapshotChangeDetector.swift:59-64`.
- **Evidence**: iPhone and watch target compiles passed; physical WatchConnectivity transfer remains unverified.

### I3. Restrict carry-forward to bridge measurements — fixed

- **What**: The merge rule accepted mock or OAuth Claude windows as prior bridge data.
- **Where**: `Sources/ApexGaugeCore/Snapshot.swift` and `Tests/ApexGaugeCoreTests/ClaudeBridgeFetcherTests.swift`.
- **Why**: Switching to the bridge while unavailable could show unrelated percentages with a bridge health banner.
- **How**: Require non-nil `capturedAt` on prior windows; that timestamp is emitted by bridge captures and absent from mock/OAuth snapshots. Implemented at `Snapshot.swift:111-119`; focused regression at `ClaudeBridgeFetcherTests.swift:245-250`.
- **Evidence**: `swift test` passed (33 XCTest and 19 Swift Testing cases).

## Minor

None.

## Remaining acceptance

The coordinator should verify the remediation commit and existing test/build receipts, then complete any device presentation/WatchConnectivity acceptance available in its pipeline. The auditor did not push, merge, rebase, or write Roadmap state. Existing follow-up §4811 owns the separate Mac-helper protocol enhancement.
