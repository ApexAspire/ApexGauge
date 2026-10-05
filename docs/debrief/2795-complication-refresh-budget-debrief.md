# Debrief: §2795 Complication refresh-budget and wake-cost pass

Plan file: n/a (complexity 3; measured against Roadmap ticket §2795).

## 1. What changed
- `ComplicationTimelineProvider.refreshInterval` raised from 15 to 30 minutes.
- `getSnapshot(in:)` no longer calls `requestRefreshIfNeeded`; it returns the cached entry only. `getTimeline` still requests a refresh.
- `ComplicationSnapshotRequester.receivePayload` previously called `reloadAllTimelines()` up to four times per payload. Logic moved to a new pure-ish `ComplicationPayloadApplier` in ApexGaugeCore (side effects injected) that requests at most one reload per payload, and none when nothing was applied.
- README line 15 now says ~30 minutes.

## 2. Decisions
- Injected closures (setData/setBool/writeSnapshot/reload) rather than a pure "should reload" function, so the test counts actual reload invocations.
- Semantics preserved: a reload is requested if any key was applied; a snapshot counts only if it decodes and the write succeeds. No staleness check was added (UsageEngine.fetch stamps fetchedAt even on failure).
- README line 68 (bridge probe every 15 minutes) is unrelated and left alone. docs/plan.md describes a 15-30 minute range as design budget; left as is.

## 3. Variances
- Instrumentation is a unit-test reload counter, not on-device logging.
- No edits to the .xcodeproj or the §2796 files.

## 4. Tests
- `swift test` : exit 0, 39 XCTest tests, 0 failures; includes 6 new `ComplicationPayloadApplierTests` (full payload = 1 reload, empty = 0, unrelated keys = 0, undecodable snapshot = 0, failed write = 0, single setting = 1).
- Not run: xcodebuild compile of WatchComplication (no simulator on host; parent runs the gate).

## 5. Outstanding
- Untethered before/after battery measurement (Watch > Settings > Battery, one day each) needs a human and a device. NOT done.

## 6. Files changed
Created:
- Sources/ApexGaugeCore/ComplicationPayloadApplier.swift
- Tests/ApexGaugeCoreTests/ComplicationPayloadApplierTests.swift
- docs/debrief/2795-complication-refresh-budget-debrief.md

Modified (git diff --stat):
- README.md (1 line)
- WatchComplication/ComplicationTimeline.swift (10 lines)
- WatchComplication/SnapshotRequester.swift (48 lines)
