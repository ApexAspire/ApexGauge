# Apex Gauge security review — 2026-08-08

> **Status:** all findings were remediated before publication (see commits after 6b42f4f): curl-and-run replaced with clone-first instructions, unsigned-binary guidance rewritten, mock mode now honoured on all refresh paths, Keychain/backup claims corrected, QR payload disclosed accurately, raw provider error bodies no longer persisted, QR renders in-memory (no disk artifact), gitignore hardened.

## Verdict: SAFE WITH FIXES

No real credential, token, private key, API key, password, provisioning profile, or certificate was found in the tracked tree or reachable Git history. The token-shaped strings in `Tests/` are synthetic, and the Claude/Codex OAuth client IDs are public client identifiers rather than secrets.

The repository is **not safe to publish or use for App Store onboarding unchanged**, however. Finding 1 gives a compromised GitHub branch/release or a local `/tmp` race a direct path to execute code that reads the user's Claude/Codex credentials. Findings 2–4 are material privacy/security gaps. Fix findings 1–4 before publication or submission; findings 5–8 should also be resolved or explicitly accepted. No credential rotation is indicated by this review.

Scope and limitations:

- Reviewed 84 tracked files, all 40 commits reachable from the two local refs (`main` and `agent/secreview`, both at `c0f933a`), the six dangling commits reported by `git fsck`, and the three tracked App Store screenshots.
- The repository has no Git remote. A normal future `git push main` will not send dangling objects or the worktree's `.git` administrative file.
- No `dist/qr-connect` release binary is present in this worktree. This review covers its source/build instructions, not any future GitHub release artifact, Developer ID signature, notarization ticket, or App Store archive.
- Static review covered the iOS/watchOS network, Keychain, snapshot, App Group, WatchConnectivity, QR, logging, entitlement, and permission paths. The QR helper self-test passed. Live provider calls and live credential flows were deliberately not exercised.

## Secrets/privacy scan (evidence: commands run, matches found or "none")

### Actual secrets

- **None found in the current tracked tree.** The tree-wide high-confidence scan covered private-key blocks; AWS, GitHub, Slack, Stripe, Google, npm, PyPI, Anthropic/OpenAI-style tokens; JWTs; generic password/client-secret/API-key/token assignments; high-entropy strings; `.env` files; signing keys; provisioning profiles; and credential filenames.
- **None found in reachable Git history.** `git log --all -p --no-color --full-history` produced zero private-key markers and two high-confidence token-shaped matches, both occurrences of the explicitly synthetic Claude fixture in `Tests/ApexGaugeCoreTests/CredentialsParserTests.swift:25-26`. Historical filename enumeration found no `.env`, credential file, private key, certificate, provisioning profile, `xcuserdata`, `dist/`, or DerivedData artifact.
- **None found in dangling commits.** `git fsck --full --no-reflogs --unreachable` found six dangling commits. Their patches produced zero high-confidence secret matches. They are not reachable from either branch and will not be transferred by a normal branch push.
- The generated JWT used by `CodexUsageFetcherTests` is constructed at test time and the other access/refresh/API-key values in `Tests/` are clearly synthetic (`acc-123`, `ref-456`, `codex-refresh`, `sk-kimi-key`, and similar).

### Personal or low-sensitivity identifiers found

- `docs/plan.md:9` exposes the local short username and source path `/Users/petersmini/Projects/CodexBar`.
- Every reachable commit records `Scott Peters <scott@apexaspire.co.uk>` as author identity. This is public if the full history is pushed. The dangling commits contain the same identity but are not pushed by a normal branch push.
- `ApexGauge.xcodeproj/project.pbxproj:466,500,534,568,600,633` contains Apple Team ID `57CS87GDZL`. A Team ID is a low-sensitivity signing identifier, not a credential, and is observable from signed products; retain it only if publisher correlation is intentional.
- `docs/app-store/privacy-policy.md:52` contains the example role address `privacy@apexaspire.co.uk`; verify the address exists before publication. `git@github.com` in `docs/app-store/submission-guide.md:20` is an SSH transport URI, not an email address.
- Visual inspection of all three tracked App Store screenshots found only synthetic quota data and status-bar times—no names, account IDs, device names, emails, notifications, UDIDs, or credentials. PNG string/metadata scans found no personal path or email.
- The worktree's untracked Git administrative file contains a local `/Users/petersmini/...` path, as expected for a linked worktree. Git does not track or publish that file.

### Negative evidence

- No `.env` file, provisioning profile, `p8`, `p12`, PEM/key/certificate file, auth file, credential JSON, `xcuserdata`, or build/distribution binary is tracked or present in reachable history.
- No runtime `http://` endpoint exists. The only `http://` strings are Apple's plist DTD identifiers. All provider, refresh, Kimi Console, raw GitHub, and GitHub release URLs use HTTPS.
- No ATS exception, arbitrary-load flag, custom `URLSessionDelegate`, custom trust evaluation, certificate bypass, or certificate pinning exists.
- No request logs or token prints exist. OAuth refresh tokens are placed in the POST body (percent-encoded form for Claude, JSON for Codex), never in a URL. Bearer credentials are placed only in request headers.
- Entitlements contain only the common App Group; there is no broad keychain-sharing, iCloud, location, microphone, contacts, health, network-extension, or associated-domain entitlement. The only privacy permission is the generated camera usage description at `ApexGauge.xcodeproj/project.pbxproj:471,504`.
- `UsageSnapshot` is structurally limited to provider enum, quota percentages, reset/fetch dates, version, and `lastError` (`Sources/ApexGaugeCore/Snapshot.swift:4-79`). It has no credential field. WatchConnectivity sends only encoded snapshots plus Boolean/JSON preferences (`App/Connectivity/PhoneConnectivityManager.swift:39-73,111-151`). UserDefaults stores only mock/display/reset/complication preferences, not credentials.

## Findings

### 1. High — credential-reading Mac helper is delivered through mutable or untrusted code paths

**Evidence:** `App/Views/Settings/ClaudeSettingsView.swift:15-18`; `App/Views/Settings/CodexSettingsView.swift:15-18`; `README.md:44-48`; `docs/app-store/submission-guide.md:46-50`; `Scripts/build-qr-connect.sh:55-56`; `docs/distribution.md:5-8`.

**Description:** The in-app command downloads `Scripts/qr-connect.swift` from the mutable `main` branch into the predictable, world-shared path `/tmp/qr-connect.swift` and immediately executes it. It provides no immutable revision, checksum, signature, or inspection pause. The alternate release path is also unsafe as currently documented: the build script applies only ad-hoc signing (`codesign --sign -`), while the submission guide calls the release an "unsigned developer build" and tells users to recursively remove Gatekeeper quarantine with `xattr -dr`. A checksum published beside an artifact on the same compromised release channel does not independently authenticate it.

**Exploit scenario:** An attacker who compromises the GitHub repository/release, or a local process that wins the predictable `/tmp/qr-connect.swift` race, substitutes Swift or binary code. The user executes it in the exact context where it can invoke `/usr/bin/security` for the Claude Code Keychain item and read `~/.codex/auth.json`; the substitute code can exfiltrate long-lived refresh tokens and execute arbitrary commands as the user. Removing quarantine suppresses the main macOS warning for a tampered unsigned binary.

**Recommended fix:** Remove the curl-and-run and quarantine-removal guidance before release. Prefer a hardened-runtime, Developer ID-signed, notarized, and stapled helper; make the release pipeline fail if it has only an ad-hoc signature, and document `codesign --verify --deep --strict` plus `spctl -a -vv` verification. If source execution remains, pin an immutable commit/tag, authenticate it with a digest embedded in the already-reviewed App Store build or another independent trust channel, download into a new mode-0700 `mktemp -d` directory, and separate download/inspection from execution. A GitHub checksum changed by the same account as the artifact is useful for corruption detection but is not a complete compromise boundary.

### 2. Medium — “Use mock data” still permits authenticated live background/watch traffic

**Evidence:** `App/Views/Settings/SettingsView.swift:30-43`; `App/ApexGaugeApp.swift:36-60`; `App/ViewModels/UsageViewModel.swift:104-113`.

**Description:** The UI promises that mock mode “Shows representative quotas without contacting providers.” Foreground refresh respects the flag by choosing `mockEngine`, but the app-level background refresh closure and watch snapshot-request handler are permanently wired to `liveEngine.refreshAll()` and are registered regardless of the persisted mock-mode choice.

**Exploit scenario:** A user connects providers, later enables mock mode specifically to stop provider contact, and backgrounds the app. A scheduled `BGAppRefreshTask` or stale paired-watch request still loads Keychain credentials and sends authenticated requests to the three provider endpoints. This violates the user's explicit network/privacy choice and can rotate OAuth credentials while they believe live access is disabled.

**Recommended fix:** Put the live/mock decision in one shared policy consulted by foreground refresh, background tasks, and both watch-request paths. In mock mode, cancel or no-op pending live background work and answer the watch from the mock/current cache without loading Keychain items. Add tests with a counting HTTP client proving zero provider requests for every invocation path while mock mode is enabled.

### 3. Medium — Keychain retention and backup claims are stronger than the platform guarantees

**Evidence:** `App/Infrastructure/KeychainCredentialStore.swift:62-78`; `App/Views/Settings/QRScannerView.swift:194-198`; `docs/app-store/privacy-policy.md:13-17,39-43`; `docs/app-store/review-notes.md:18-24`.

**Description:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is an appropriate background-accessible, non-synchronizing choice, but `ThisDeviceOnly` means that an item does not migrate to another device—not that it is necessarily absent from every backup. More importantly, uninstalling an app does not call `SecItemDelete`, and Apple does not guarantee deletion of an app's Keychain items on uninstall. The policy nevertheless promises both “not included in backups” and “Deleting the app removes the credentials.” Apple's documentation describes the actual [After First Unlock, This Device Only semantics](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly), and Apple DTS explicitly advises apps that require uninstall deletion to [entangle the secret with a key stored in the app container](https://developer.apple.com/forums/thread/36442).

**Exploit scenario:** A user deletes Apex Gauge believing the provider tokens are gone. The Keychain entries can remain on that device and become readable again after reinstall by a later build with the same signing/access-group identity. The user therefore has retained live credentials after following the documented deletion action.

**Recommended fix:** Correct the privacy policy, review notes, and in-app copy to say that the items do not synchronize or migrate to another device and that “Disconnect” explicitly deletes them. Tell users to disconnect/revoke providers before uninstall if immediate deletion matters. For a technical uninstall guarantee, encrypt/entangle each Keychain payload with a random key stored only in the app container (or use a robust fresh-install marker that deletes inaccessible/stale items before reuse), then test uninstall/reinstall behavior. Keep `AfterFirstUnlockThisDeviceOnly` only if locked-device background refresh remains a stated product requirement.

### 4. Medium — the QR secret is persisted and handed to an arbitrary default image viewer

**Evidence:** `Scripts/qr-connect.swift:215-264,315-365`.

**Description:** `mkdtemp` correctly creates a private temporary directory and the helper removes its original directory on normal/error paths and four common signals. However, the code writes the complete credential QR to a PNG and passes it to `NSWorkspace.shared.open`, which grants the user's default PNG handler access. The helper cannot control that app's cache, recent-item behavior, sync behavior, crash handling, or copies. Cleanup also cannot cover `SIGKILL`, process crashes, power loss, and currently unhandled termination such as `SIGPIPE`; those paths can leave the private on-disk original behind.

**Exploit scenario:** A malicious or compromised default image viewer receives a file containing a refresh token (and currently sometimes a Claude access token) even though it could not read the Claude Code Keychain item directly. It uploads or retains the image after the helper deletes only its own copy. A crash/kill can likewise leave the QR artifact until temporary-directory cleanup.

**Recommended fix:** Render the `CGImage` inside an in-process AppKit window and never create or open a PNG. Keep the payload only in memory, close the window immediately after confirmation, and zero/release buffers where practical. If an on-disk fallback remains, explicitly document the extra viewer trust boundary, exclude the file from backup, retain the private directory, add `defer`/`atexit` cleanup and safe handling for `SIGPIPE`, and acknowledge that forced termination can never guarantee deletion.

### 5. Low — public descriptions understate the Claude QR payload

**Evidence:** `Sources/ApexGaugeCore/CredentialsParser.swift:105-120`; `Scripts/qr-connect.swift:143-155`; `README.md:52`; `docs/app-store/review-notes.md:18-24`.

**Description:** The README and App Review notes say the QR contains only an OAuth refresh token (plus Codex's non-secret account ID). Current Claude payloads also include the current access token and its expiry when the encoded payload remains below 2,500 bytes. The exact payload fields are `type`, `provider`, `refreshToken`, optional `accountID`, optional `accessToken`, and optional `accessTokenExpiresAtMs`; no other credential/account data crosses the QR channel.

**Exploit scenario:** A user exposes or records the QR based on a narrower disclosure and unknowingly exposes both Claude token forms. The refresh token already has the greater long-term authority, which limits the incremental impact and keeps severity low, but the disclosure is still inaccurate.

**Recommended fix:** Either remove the Claude access token/expiry to match the stated design, or accurately disclose the conditional access token everywhere (README, review notes, privacy policy, and in-app explanation). Keep the QR deletion/revocation warning explicit.

### 6. Low — raw provider error bodies become persistent cross-device snapshot data

**Evidence:** `Sources/ApexGaugeCore/Providers/ProviderSupport.swift:23-35`; `Sources/ApexGaugeCore/UsageEngine.swift:41-58`; `App/ViewModels/UsageViewModel.swift:203-220`; `Sources/ApexGaugeCore/Snapshot.swift:49-62`; `App/Infrastructure/SnapshotStore.swift:14-16`; `App/Connectivity/PhoneConnectivityManager.swift:39-73`.

**Description:** For non-401/403/429 failures, the first 500 characters of the provider response body are put in `UsageFetchError.http`, rendered to the user, stored as `ProviderSnapshot.lastError` in both App Group snapshot files, and sent to the paired watch. Although credentials are not part of the request snapshot, the app cannot guarantee that a provider error body will not echo account data, a token fragment, diagnostic identifiers, or other sensitive text.

**Exploit scenario:** A provider or compromised provider edge returns an error containing an email, account identifier, or echoed credential. Apex Gauge persists and transfers that text beyond the original network response and may display it on screen. Fixed HTTPS endpoints mean ordinary remote attackers cannot directly choose this body, so severity is low.

**Recommended fix:** Never put raw response bodies into `UsageSnapshot`. Persist only a stable status code and a generic, user-actionable message. If diagnostics are needed, keep a bounded, redacted body in ephemeral local memory; redact token/JWT/email patterns before any display. Add a test whose error body contains a synthetic token and assert that it is absent from UI/snapshot/WatchConnectivity data.

### 7. Low — the repository identifies the developer and signing team

**Evidence:** `docs/plan.md:9`; `ApexGauge.xcodeproj/project.pbxproj:466,500,534,568,600,633`; Git author metadata for all 40 reachable commits (metadata has no file line).

**Description:** The tree exposes the local username/path and Apple Team ID; the full Git history exposes the developer's name and corporate email. None is an authentication secret, and company/publisher attribution is partly intentional, but the combined data makes personal and portfolio correlation easier.

**Exploit scenario:** A hostile reader correlates the local username, publisher, signing team, Git identity, and other public projects for targeted phishing or account-recovery social engineering. These values do not by themselves enable signing or account access.

**Recommended fix:** Replace the absolute source path with a repository-relative/generic reference. Decide explicitly whether the name/email and Team ID are intended public attribution. If not, re-author/squash the local history with a GitHub noreply or role address before the first push and move the Team ID to an untracked local build setting where practical. Do not rewrite after publication and assume old data disappeared from forks/caches.

### 8. Low — `.gitignore` omits common future secret/signing artifacts

**Evidence:** `.gitignore:14-22`.

**Description:** Current credential-specific ignores cover `*.credentials.json` and `auth.json`, and build/dist paths are covered, but `.env`, `.env.*`, provisioning profiles, private signing keys, and common certificate containers are not ignored. No such file exists now; this is a preventive-control gap.

**Exploit scenario:** A future contributor adds an environment file, App Store Connect `.p8` key, Developer ID `.p12`, PEM key, or development provisioning profile (which may contain device UDIDs and signing metadata), and Git stages it by default.

**Recommended fix:** Add `.env`, `.env.*` (with an explicit `!.env.example` if desired), `*.mobileprovision`, `*.p8`, `*.p12`, `*.pem`, and appropriate private-key patterns. Add a maintained secret scanner/pre-commit or CI gate; ignores reduce accidents but do not protect forced adds or renamed secrets.

## Known-public items (not leaks)

- Claude OAuth client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e` and Codex OAuth client ID `app_EMoamEEZ73f0CkXaXp7hrann` are public first-party client identifiers, also published in the MIT-licensed CodexBar project. They confer no authentication authority without a user's token.
- Token-shaped and credential-like values under `Tests/` and the QR helper self-test are synthetic fixtures.
- The usage/refresh endpoints are public network locations: `api.anthropic.com/api/oauth/usage`, `platform.claude.com/v1/oauth/token`, `chatgpt.com/backend-api/wham/usage`, `auth.openai.com/oauth/token`, and `api.kimi.com/coding/v1/usages`.
- Bundle IDs, App Group ID, background task ID, complication kind, GitHub organization/repository name, product name, copyright holder, public support/privacy URLs, and release SHA-256 checksums are identifiers or integrity metadata, not secrets.
- Apple Team ID `57CS87GDZL` is low-sensitivity publisher metadata, not a private signing key or provisioning credential.

## Residual risks accepted by design

- Claude and Codex quota endpoints are unofficial/undocumented. They can change, rate-limit, reject the public clients, or create provider-policy/App Review risk without a code change. This is availability/policy risk rather than a repository secret.
- The optical QR channel intentionally exposes a bearer refresh token to anything that can see/record the code. Users must control the room/screen and revoke/regenerate provider credentials if a QR is photographed or leaked. Fixing finding 4 removes unnecessary disk/viewer exposure but not this optical risk.
- Codex refresh tokens rotate. Making the phone the refresh owner can invalidate the Mac lineage (or vice versa); the documented re-paste flow is an accepted availability risk.
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps credentials available after the first device unlock so background refresh can run while the device is relocked. This is less restrictive than foreground-only `WhenUnlocked`, but is consistent with the background-refresh design and does not sync/migrate to another device.
- Standard `URLSession` trust evaluation is used with no pinning. This is appropriate for provider certificate rotation but trusts the system CA store, including roots the user explicitly installs/trusts.
- Quota percentages, reset times, fetch times, and sanitized errors are intentionally stored in App Group containers and sent to the paired watch. Complication views apply `.privacySensitive()` at `WatchComplication/ComplicationViews.swift:9-12,24-27`.
- Forced termination (`SIGKILL`), process crash, and power loss cannot guarantee cleanup of an on-disk secret. The preferred mitigation is finding 4's no-file, in-process rendering rather than broader signal handling.
- Future GitHub release binaries and App Store archives remain outside this repository review and require separate signature, notarization, entitlement, and artifact-hash verification.

## Commands run

Repository/ref/inventory:

```sh
git status --short --branch
git remote -v
git show-ref
git ls-files
find . -path './.git' -prune -o -type f -print | sort
git ls-files -z | xargs -0 wc -c
git ls-files -z | xargs -0 file
git ls-files -s
git rev-list --all --count
git log --all --date=iso-strict --format='%H %ad %an <%ae> %s'
git log --all --name-only --format= | sed '/^$/d' | sort -u
```

Current-tree and history secret/privacy scans (values were not emitted for high-confidence history matches):

```sh
rg -n --hidden --glob '!.git/**' <private-key/token/password/email/path/team-id patterns> .
rg -n -I --hidden --glob '!.git/**' -e '[A-Za-z0-9_+/=-]{32,}' .
git log --all -p --no-color --full-history | rg -a -o -e <high-confidence-secret-patterns> | wc -l
git log --all --format='%H' --name-only -G <high-confidence-secret-patterns>
git log --all -p --no-color --full-history | rg -a -o -e '-----BEGIN ... PRIVATE KEY-----' | wc -l
git log --all --format='%H' --name-only -G <personal-path/email/team-id-patterns>
git rev-list --objects --all ... git cat-file ... rg <generic-secret/personal-patterns>
git fsck --full --no-reflogs --unreachable
git show --no-color <six-dangling-commit-ids>
git show --no-color <six-dangling-commit-ids> | rg -a -o -e <high-confidence-secret-patterns> | wc -l
strings -a <each tracked PNG> | rg <path/email/author/device-metadata-patterns>
sips -g software -g creator -g description <source PNGs>
```

Security/data-flow review:

```sh
nl -ba <all credential, parser, provider, snapshot, app, watch, complication, entitlement, plist, helper, test, and release-document files>
rg -n <logging/output patterns> .
rg -n <network/trust/URL/header/body patterns> .
rg -n <storage/Keychain/UserDefaults/WatchConnectivity patterns> App Watch WatchComplication Sources Scripts
rg -n <Process/system/exec/mkdtemp/xattr/curl patterns> .
rg -n <force-cast/force-unwrap patterns> --glob '*.swift' .
rg -n -i '(script|foreignObject|href=|xlink:href|data:|https?://)' Shared/Assets.xcassets --glob '*.svg'
rg -n '(PBXShellScriptBuildPhase|shellScript|OTHER_SWIFT_FLAGS|OTHER_CODE_SIGN_FLAGS)' ApexGauge.xcodeproj/project.pbxproj
git check-ignore -v --no-index .env .env.local secret.env foo.mobileprovision key.p8 cert.p12 private.pem auth.json sample.credentials.json dist/qr-connect build/out DerivedData/out
plutil -lint App/Info.plist App/ApexGauge.entitlements Watch/ApexGaugeWatch.entitlements WatchComplication/Info.plist WatchComplication/ApexGaugeComplication.entitlements
swift Scripts/qr-connect.swift --selftest
```

Validation results:

- Plists/entitlements: all linted `OK`.
- QR helper self-test: `SELFTEST OK 165 payload bytes` (first sandboxed compiler-cache attempt was blocked; the permitted rerun passed).
- No build or full Swift test suite was run: this was a source/history security review, and the requested terminal status records validation as `n/a — review`.
- Two exploratory history-loop attempts were discarded rather than treated as evidence: one used zsh's special `path` variable and broke command lookup; the next omitted `rg -e` for a leading-dash private-key regex. The final single-pass `git log --all -p` scans above succeeded. One separate exploratory `git log -G` generic-pattern command had a shell quoting error and was not used.
