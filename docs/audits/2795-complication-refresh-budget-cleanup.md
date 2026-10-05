# Cleanup Plan: §2795 complication refresh budget and wake cost

**Source**: `docs/audits/2795-complication-refresh-budget-audit.md`
**Generated**: 2026-10-05
**Fixed implementation range**: `9502a5cb4b237d57012ae760ab9526b72f37f11f..07003d6cffb70ee3b026ee3902ef4ca535fadf3a`
**Total items**: 2 (0 critical, 2 important, 0 minor); one important fixed, one important open.

## Critical

None.

## Important

### I1. Restore fixed debrief provenance and full file inventory — fixed

- **What**: The original debrief lacked fixed base/end SHAs and omitted the committed swarm record from §6.
- **Where**: `docs/debrief/2795-complication-refresh-budget-debrief.md`.
- **Why**: The deterministic debrief checker was blocked, and audit coverage could not be reconciled to the commit.
- **How**: The pipeline auditor reconstructed the record from the fixed parent and implementation commit, added all seven paths, and reran `node /Users/petersmini/agent-dotfiles/scripts/check-debrief-diff.js docs/debrief/2795-complication-refresh-budget-debrief.md`. Result: PASS, 7/7 paths, no advisory. No further source action is needed.

### I2. Complete the untethered battery comparison — open external acceptance

- **What**: Roadmap §2795 requires one untethered day before and one after the refresh change. Neither day's physical-device reading is recorded.
- **Where**: Roadmap §2795 scope bullet 4; debrief §5 and the committed swarm record's Outstanding section.
- **Why**: Unit reload counts and compile-only builds cannot establish actual watch wake or battery savings. A before measurement taken only after this commit is not a historical baseline.
- **How**: The coordinator should retain a typed device acceptance step. Use a physical paired watch with debugger disconnected, record watchOS/build/revision, face/complication, battery start/end and elapsed time for a 24-hour baseline on the prior revision and a comparable 24-hour run on the changed revision. If the prior revision cannot be run, label the later run as a new controlled comparison rather than a historical before/after result. Record the evidence locator and decision on §2795 before claiming full ticket acceptance.
- **Pipeline disposition**: skipped in this stage because no physical watch or two-day measurement window is available. No code change can discharge it.

## Minor

None.

## Verification and handback

- Focused applier suite: 6/6 passed locally with SwiftPM sandbox disabled.
- Debrief/diff checker: PASS, 7/7.
- Coordinator record: full Swift suite and three compile-only device-SDK target builds passed; asset catalogs and device behavior remain untested.
- Audit verdict: **concerns** while I2 remains open. The coordinator owns the next decision and Roadmap state; the pipeline auditor made no Roadmap write, push, merge or rebase.
