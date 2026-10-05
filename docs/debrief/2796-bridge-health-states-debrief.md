# §2796 Bridge health states: debrief

Plan file: n/a (complexity 3; measured against Roadmap ticket §2796).

## What changed and why
`ClaudeBridgeFetcher` threw `UsageFetchError.notConfigured` for three causes, so every surface showed a generic "Not configured"/stale Claude row. It now returns a modelled result and the state travels as data.

- Core: `ClaudeBridgeState` (`iCloudUnavailable`, `noCapture`, `noWindows`) with shared copy (`title`, `detail`, `watchText`); `ClaudeBridgeReading` (`available` / `unavailable(state)`); `ClaudeBridgeFetcher.read()`. `fetchUsage()` returns an empty-window `ProviderSnapshot` carrying `bridgeState` instead of throwing. Decode failure and newer-version still throw.
- `ProviderSnapshot.bridgeState` is optional and additive; custom `init(from:)` decodes it leniently (unknown future value -> nil). `UsageSnapshot.version` not bumped.
- Staleness is untouched: stays `capturedAt` + "Measured Xh ago" (amber past 5h). A stale capture is NOT a bridge state.
- Dashboard: `ProviderCardView` shows an actionable banner when windows are empty and `bridgeState` is set; the "Measured ..." label is hidden then (no capture to age).
- Watch: Claude section shows `watchText` ("Bridge idle", ...) when the phone has sent a snapshot but the bridge is quiet; "Waiting for iPhone" remains solely for "no snapshot received".
- Settings bridge row now uses the same `read()`, so Settings and card cannot disagree; wording reused ("iCloud unavailable", "Waiting for the Mac bridge", "Receiving (Nm ago)").

## State table
| Cause | Detected how | Dashboard / Settings copy | Watch copy |
|---|---|---|---|
| iCloud signed out / Drive off / container missing | `locateContainer()` nil | "iCloud unavailable" + sign in to iCloud, enable iCloud Drive for Apex Gauge | "iPhone iCloud is off" |
| Helper not installed, Claude Code not run, OR plan has no `rate_limits` (all one case) | container ok, file read fails | "Waiting for the Mac bridge" + install bridge, use Claude Code on Pro/Max; appears after first reply in a session | "Bridge idle" |
| Snapshot present, no windows | decoded, all windows nil | "Bridge has no usage figures" + Pro/Max only, after first reply | "Bridge idle: no usage sent" |
| Healthy but old | `capturedAt` age | unchanged "Measured Xh ago", amber >5h | unchanged |
| Phone not yet sent data | watch has no snapshot | n/a | "Waiting for iPhone..." (unchanged) |

## Decisions and honest limits
- "Helper never installed" vs "Claude Code not run recently" vs "Pro/Max unmet" are NOT separable on-device: `Scripts/apexgauge-bridge.swift` (`runStatusline`) writes no capture at all when `rate_limits` is absent, so all three look like a missing file. They share `.noCapture` and the copy names the possibilities. `.noWindows` is only reachable from a file written by something other than the current helper; kept for robustness. Separating the Pro/Max case properly needs a helper protocol change (e.g. publish a heartbeat/`reason` file) - not done (out of scope per brief); see follow-up.
- `.project-log.md` absent; the Pro/Max + first-API-response constraint was confirmed in README.md:44 and Scripts/apexgauge-bridge.swift:162.
- Compatibility: old phone -> new watch: field absent -> nil. New phone -> old watch: unknown key ignored (old watch shows an empty Claude section, as before). Future unknown state -> nil.

## Variances
- Review fix: `ProviderSnapshot.carryingForward(from:)` (Snapshot.swift) is called by `UsageViewModel` on both refresh paths. An unavailable reading with prior windows keeps those windows, `capturedAt` and `fetchedAt` and attaches the new state, matching the old failed-path parity; a healthy read clears the state. The card shows the banner above windows and keeps the "Measured" label when a capture exists; the watch shows its label above any window rows.
- Complication (`WatchComplication/`) not changed; it sees empty windows as before.

## Tests
- `swift test --filter ClaudeBridgeFetcherTests`: 18 tests passed (3 old throw tests replaced by state tests; added copy, stale-is-not-a-state, Codable compat tests).
- `swift test --filter UsageEngineTests`, `--filter SnapshotTests`: 1 test each, 0 failures.
- `swiftc -parse` OK on the three edited App/Watch files.

## Not verified
UI rendering (card banner, watch Label, Settings row), iOS/watch builds (xcodebuild not run), on-device WatchConnectivity, accessibility/dynamic type.

## 6. Files changed
From `git status --porcelain`:
- M App/ViewModels/UsageViewModel.swift
- M App/Views/Components/ProviderCardView.swift
- M App/Views/Settings/ClaudeSettingsView.swift
- M Sources/ApexGaugeCore/Providers/Claude/ClaudeBridgeFetcher.swift
- M Sources/ApexGaugeCore/Snapshot.swift
- M Tests/ApexGaugeCoreTests/ClaudeBridgeFetcherTests.swift
- M Watch/ContentView.swift
- ?? docs/debrief/2796-bridge-health-states-debrief.md
