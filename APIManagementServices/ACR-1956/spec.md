---
status: implemented_done
status-updated: 2026-11-24
---
# ACR-1956: Azure API Management Service Security Issue

## Scope

**Subscription selection:** After sign-in the script lists the account's Azure subscriptions,
the user picks one, its APIM services are processed, and the user is then asked whether to
select another subscription or finish. Summary and exit code cover all picked subscriptions.

Microsoft advisory MZK9-GH0 (APIM Classic tiers): secrets stored in APIM may have been accessed before
the platform fix of 2026-11-19. The fix does not invalidate credentials already exposed. Potentially
exposed: Named Values secrets, identity-provider client secrets, OpenID Connect provider client secrets,
subscription keys, management API tokens. Recommended action: rotate all credentials stored in APIM.

Ticket (JIRA type Incident, P1 - Critical, S1 - Blocking; linked: STAR-3851 clone, ATB-305 "Rotate JWT Secret for the Ayuda Platform").

Platforms named in the ticket comments:
- **Ayuda**: rotate all API subscription keys. JWT tokens (stored in user notes) and their secret need replacing separately (see ATB-305).
- **Broadsign Static**: rotate subscription keys; Auth0 client id also exposed (replacement optional).

Rotation options raised to IT Security (decision pending there): (1) rotate primary and secondary at once (clients lose access); (2) rotate secondary first, notify clients to use secondary, then rotate primary (no interruption for clients on primary).

Developer Portal Basic Authentication was unintentionally disabled by Azure; Azure recommends re-enabling it in the portal (Developer portal > Identities) so users can retrieve new keys.

Project scope (from AGENTS.md): a PowerShell script rotating credentials in Azure API Management, based on
https://techcommunity.microsoft.com/blog/integrationsonazureblog/rotating-credentials-in-azure-api-management/4575478
- Out of scope: Named values are NOT rotated.
- Requirement sources: Subscription - Regenerate Primary Key / Regenerate Secondary Key REST APIs.

## Closed decisions (round 2, user answers)

- D1 Rotation order: no fixed order. Run-time flag `-RotateKey Primary|Secondary|All` (user chooses).
- D2 Discovery: all Azure subscriptions available to the signed-in user are listed/checked; subscriptions without APIM services are skipped; for each APIM service found, the user approves before any change.
- D3 Target granularity: one APIM service at a time.
- D4 Secrets scope: identity-provider, OpenID Connect and Auth0 secrets are only checked and reported; only subscription-key rotation is offered. Named values: inventory only, NEVER rotated.
- D5 Key distribution: users get new keys from the Developer Portal (Basic Auth re-enabled, no longer open). Key values are never logged. A run protocol/log states which key was rotated for whom (IT Security audit).
- D6 Safety: `-WhatIf`/ShouldProcess, continue past per-item failures, retry on 429/5xx, final summary, non-zero exit code if any failure.
- D7 Auth/API: Az module, `Invoke-AzRestMethod` with the signed-in identity.
- D8 Rejecting an operation on one APIM service never blocks the run: skip to the next service/subscription. Run ends when all are analysed, rotated or rejected.

## User's script design (requirements)

1. Login to Azure; list all subscriptions available to the user; per subscriptionId get the APIM service resources.
2. Per APIM service inventory and report: subscription keys (metadata only), named values, backends, OAuth and identity providers, Developer portal sign-in providers, Credential Manager providers, loggers, product policies.
3. Check whether any APIM User has a non-empty Note. NEVER read/report/persist Note content; only empty vs non-empty. When non-empty report Full Name, Email, State, Identity and Groups.
4. Ask the user to confirm rotating Primary, Secondary or both (flag from D1).
5. After execution write a report stored in the project with everything IT Security needs; then ask whether to continue with the next subscription/APIM service.
6. Rotation via REST: Subscription - Regenerate Primary Key / Regenerate Secondary Key.

## Acceptance Criteria

<!-- derived from user answers of rounds 2 and 3; all decisions closed. -->

- [ ] AC1: The script regenerates the primary and/or secondary key of APIM subscriptions via the Regenerate Primary Key / Regenerate Secondary Key REST APIs, selected by `-RotateKey Primary|Secondary|All`.
- [ ] AC2: Named values, identity-provider, OpenID Connect and Auth0 secrets are never modified (inventory/report only).
- [ ] AC3: All accessible Azure subscriptions are enumerated; those without APIM are skipped; APIM services are processed one at a time.
- [ ] AC4: No key is regenerated on an APIM service without explicit user approval for that service; a rejection skips to the next without stopping the run.
- [ ] AC5: The inventory per APIM service covers the items listed in the design (item 2) and the Note empty/non-empty check (item 3) without ever reading or emitting Note content.
- [ ] AC6: No key value (primary/secondary, old or new) appears in console, log or report.
- [ ] AC7: A report/protocol per run states, per APIM service and subscription: which key (Primary/Secondary) was rotated, for whom (subscription display name/id, owner/user), when, by which identity, result.
- [ ] AC8: `-WhatIf` performs no change; 429/5xx are retried; failures do not stop the run; a summary is printed; exit code is non-zero if any failure.
- [ ] AC9: The built-in master / all-access subscription is rotated only after a separate explicit confirmation; only `active` subscriptions are ever rotated.
  - Clarification: "master" = the APIM built-in all-access subscription (display name "Built-in all-access subscription", sid `master`), NOT an Azure subscription. The separate master confirmation prompt MUST display this Microsoft warning verbatim: "All-access subscription enables access to every API in this API Management instance and should only be used by authorized users. Never use it for routine API access or embed the all-access key in client apps."- [ ] AC10: Reports go to `APIManagementServices/reports/<yyyyMMdd-HHmmss>/` (`<service>.md` + `rotation-log.csv` with service, subscription, key rotated, owner, timestamp, signed-in identity, result); REST calls use `api-version=2024-05-01` via `Invoke-AzRestMethod` with only `Az.Accounts` required; Note content is discarded from memory right after the empty/non-empty check.
  - [ ] AC11: Every approval AND rejection (per-service level and master level, master separately) is recorded in `rotation-log.csv` and in the per-service `.md` with: who decided (signed-in identity), decision (approved/rejected), timestamp, Azure subscription, APIM service, scope (Primary/Secondary/All; Master), and the outcome of the action. Rejections and skips are logged too. No key values, no Note content. Extends the AC7/AC10/D11 columns per ADR-005 item 6.
## Tech ToDo (Implementation Plan)

<!-- inferred -->

1. PowerShell script (Az.Accounts, `Invoke-AzRestMethod`) following the Microsoft article: Connect-AzAccount, enumerate subscriptions, find `Microsoft.ApiManagement/service` per subscription.
2. Inventory functions per APIM service (subscriptions, namedValues, backends, authorizationServers, openidConnectProviders, identityProviders, portalsettings signin, authorizationProviders, loggers, product policies, users+groups for Note check).
3. Rotation function: POST `.../subscriptions/{sid}/regeneratePrimaryKey|regenerateSecondaryKey?api-version=<pinned>`, retry/backoff on 429/5xx, ShouldProcess.
4. Per-service confirmation loop, continue-on-reject, continue-on-failure, summary and exit code.
5. Report writer (no secrets, no Note content) into the project.
6. Tests/dry-run with `-WhatIf` against a non-production APIM.

## Closed decisions (round 3, user answers)

- D9 api-version: GA, pinned to `2024-05-01` (no preview).
- D10 Built-in `master` / all-access subscription: INCLUDED in scope (the advisory affected all subscription keys, so master is impacted). Rotating master requires a SEPARATE explicit confirmation, distinct from the per-service approval of D2. Only subscriptions in state `active` are rotated. Azure subscriptions with no APIM service are still skipped. (The earlier "ignore master" was a misunderstanding of "master" as an Azure subscription without APIM; corrected by the user.)
  - Terminology (applies to every "master" in this spec and in ADR-003): "master" means the APIM built-in all-access subscription (display name "Built-in all-access subscription"), not an Azure subscription. Microsoft wording, verbatim: "All-access subscription enables access to every API in this API Management instance and should only be used by authorized users. Never use it for routine API access or embed the all-access key in client apps." The master confirmation prompt displays this text to the user.- D11 Report: `APIManagementServices/reports/<yyyyMMdd-HHmmss>/` with `<service>.md` per service (human) + `rotation-log.csv` (machine). Each line: service, subscription, key rotated, owner, timestamp, signed-in identity, result. No key values, no Note content.
- D12 Az modules: `Az.Accounts` only, calls through `Invoke-AzRestMethod`. No Az.ApiManagement / Az.Resources dependency.
- D13 Note check: the Users API returns `note` so content transits memory. The script keeps only the yes/no result, discards the content from memory immediately, never logs or persists it. User decision ("yes, do it"). IT Security sign-off for this handling is the user's responsibility, not verified by this spec.

## Closed decisions (round 4, user answers)

- D14 No unattended mode (no `-Force` / automatic mode), by user decision. Reason: the user wants everything that happened tracked, and who approved it.
- D15 Decision audit: every approval AND every rejection (per-service and master level) is recorded in `rotation-log.csv` and the per-service `.md` with who decided (signed-in identity), decision, timestamp, subscription, APIM service, scope (Primary/Secondary/All; master separately) and outcome. Rejections and skips are logged too. No key values, no Note content. Reconciled in ADR-003 (item 8) and ADR-005 (item 6); acceptance criterion AC11.
- D16 Tooling: tests target Pester 6.2.0 (installed; >= 5 syntax). The planner adds a version pre-check (fail clearly if Pester < 5), not an upgrade task.

## Expected behavior

- Normal: login, enumerate all Azure subscriptions, skip those without APIM; per APIM service (one at a time) inventory, Note empty/non-empty check, ask approval; on approval regenerate the key(s) chosen by `-RotateKey` for every `active` subscription via REST (`api-version=2024-05-01`); write report; ask whether to continue.
- Master / all-access subscription: listed in the inventory; rotated only after its own separate explicit confirmation; without it, it is left untouched and reported as not rotated.
- Non-active subscriptions (suspended, cancelled, etc.): listed, never rotated.
- Rejection of a service (or of master): skip to the next, run is not blocked (D8).
- `-WhatIf`: no change, no regenerate call, report marks items as simulated.
- Failure: 429/5xx retried with backoff; a per-item failure is recorded and the run continues; final summary; non-zero exit code if any failure.
- Note: only empty/non-empty is retained; for non-empty, Full Name, Email, State, Identity, Groups are reported; Note content never appears anywhere.
- Secrets: no key value (old/new) in console, log or report. Named values, identity-provider, OIDC and Auth0 secrets are inventory-only, never rotated.

## Success criteria

- Every AC1-AC10 is verifiable on a non-production APIM with `-WhatIf` and a real run.
- Report folder contains `<service>.md` per processed service and `rotation-log.csv` with the D11 columns; a search of all outputs finds no key value and no Note content.
- Only `Az.Accounts` is required to run the script.
- Master rotation never happens without its separate confirmation.
- Exit code is 0 only when no failure occurred.

## Design

- Design required: YES
- Reasoning: new component with no existing pattern (system-patterns.md has no code), security-sensitive (handles credentials, performs irreversible key regeneration), with cross-cutting choices (secret handling, approval gating, retry on non-idempotent calls, audit format) that constrain implementation.
- Figma design context: not applicable (no UI). Miro: none supplied. Context7: not used (Az.Accounts/REST only, api-version pinned by D9). Database schema: not applicable.

### Components touched
New only: `APIManagementServices/Invoke-ApimKeyRotation.ps1`; output folder `APIManagementServices/reports/<ts>/`. Functions: `Invoke-ApimRequest` (wrapper: Invoke-AzRestMethod, retry, paging, error mapping), `Get-ApimInventory`, `Test-UserNotes`, `Invoke-KeyRotation`, approval helpers (service / master), `Write-ServiceReport`, `Add-RotationLogRow`, summary/exit. Tests: Pester 6.2.0 installed (>= 5 syntax, D16); planner adds a version pre-check, not an upgrade task. Decision audit (D15): approval helpers call `Add-RotationLogRow` with a `decision` event immediately on each answer (approve or reject), and `Write-ServiceReport` adds a "Decisions and outcomes" section.

### Data flow
1. `Connect-AzAccount` if no context → `Get-AzContext` identity.
2. `GET /subscriptions?api-version=2022-12-01` (ARM, via Invoke-AzRestMethod -Path) → per subscription `GET /subscriptions/{id}/providers/Microsoft.ApiManagement/service?api-version=2024-05-01`; empty → skip (D2).
3. For one service at a time: inventory GETs (subscriptions, namedValues, backends, authorizationServers, openidConnectProviders, identityProviders, portalsettings/signin, authorizationProviders, loggers, products + policies, users + groups) → allow-list projection (ADR-002) → Note boolean check.
4. service-level approval → master-level approval (APIM built-in all-access subscription, not an Azure subscription; prompt displays the Microsoft warning verbatim, see Contracts) → per active subscription POST regenerate Primary/Secondary per `-RotateKey` (ShouldProcess) → log row per action → `<service>.md` → "continue?".
5. Summary + exit code (ADR-004).

### Contracts
- ARM base `https://management.azure.com`; APIM paths `/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{svc}/...?api-version=2024-05-01`.
- Rotation: `POST .../subscriptions/{sid}/regeneratePrimaryKey` and `.../regenerateSecondaryKey`; expected 204, no body used. Master sid is `master`.
- "master" = APIM built-in all-access subscription (display name "Built-in all-access subscription"), not an Azure subscription. The Level 2 (master) confirmation prompt MUST display, before asking, this Microsoft warning verbatim: "All-access subscription enables access to every API in this API Management instance and should only be used by authorized users. Never use it for routine API access or embed the all-access key in client apps." Acceptance: a test asserts the prompt text contains this warning.- Forbidden calls: any `listSecrets`, `listValue`, `/token` action.
- CLI: `-RotateKey Primary|Secondary|All` (mandatory), `-WhatIf`, `-Confirm` (never bypasses approvals; ADR-003), optional `-OutputRoot` defaulting to `APIManagementServices/reports`.
- CSV: `Service, Subscription, KeyRotated, Owner, Timestamp, SignedInIdentity, Result, AzureSubscription, EventType, Decision, Scope, Outcome` (ADR-005 item 6; AC11). Decision rows are written for every approval and rejection, never containing key values or Note content. Exit code 0/1 (ADR-004).

### Cross-repository impact
None in code. Operational follow-ups outside this script: re-enable Developer Portal Basic Auth, ATB-305 JWT secret rotation, Auth0 client id replacement (Broadsign Static), client key hand-off.

### Architecture decisions
- ADR-001: Script structure — single dot-source-safe script, one REST wrapper, Az.Accounts only (`decisions/ADR-001-script-structure.md`)
- ADR-002: Secret-safe data handling — allow-list projection, no listSecrets, Note → boolean (`decisions/ADR-002-secret-safe-data-handling.md`)
- ADR-003: Two-level approval gate + ShouldProcess; no unattended mode (user decision D14); every decision audited (D15) (`decisions/ADR-003-approval-gating-and-whatif.md`)
- ADR-004: Retry 429/5xx, no retry on ambiguous POST, failure isolation, exit code (`decisions/ADR-004-resilience-and-exit-code.md`)
- ADR-005: Report layout, incremental audit CSV, decision audit columns (amended D15) (`decisions/ADR-005-report-and-audit-log.md`)

### Pattern deviations
None — system-patterns.md records no patterns yet; these ADRs establish them (error handling, API versioning, configuration).

## Implementation Plan

Notes: the spec has no `## Scenarios` section; coverage is traced to AC1-AC11 (and D16). All paths are under `APIManagementServices/`. Tests: Pester 6.2.0 already installed (D16): task 2 adds a version pre-check (fail clearly if Pester < 5), no upgrade task. No database, no external library beyond Az.Accounts (Context7 not used). No unattended mode (D14).

### Task 1: Script skeleton (all functions, not-implemented bodies)
- Track: code
- Blocker: skeleton
- Covers: AC1-AC11 (code surface only, no logic)
- Files: APIManagementServices/Invoke-ApimKeyRotation.ps1
- Depends on: none
- Verifiable by: dot-sourcing the script loads without error and exposes Invoke-ApimRequest, Get-ApimInventory, Test-UserNotes, Invoke-KeyRotation, approval helpers, Write-ServiceReport, Add-RotationLogRow; each throws not-implemented when called

### Task 2: Pester runner with version pre-check
- Track: test
- Covers: D16 (tooling; enables verification of AC1-AC11)
- Files: APIManagementServices/tests/Invoke-Tests.ps1, APIManagementServices/tests/Preflight.Tests.ps1
- Depends on: 1
- Verifiable by: runner exits non-zero with a clear message when Pester < 5 and runs the suite on 6.2.0; Preflight test passes

### Task 3: Tests for REST wrapper (Invoke-ApimRequest)
- Track: test
- Covers: AC8, AC6, AC10
- Files: APIManagementServices/tests/Invoke-ApimRequest.Tests.ps1
- Depends on: 1, 2
- Verifiable by: tests fail (not-implemented) then assert api-version=2024-05-01 constant, retry/backoff on 429/5xx, no retry on ambiguous POST (ADR-004), paging, no forbidden calls (listSecrets/listValue/token), error messages free of key values

### Task 4: Tests for discovery, inventory and Note check
- Track: test
- Covers: AC2, AC3, AC5, AC6
- Files: APIManagementServices/tests/Inventory.Tests.ps1
- Depends on: 1, 2
- Verifiable by: tests assert Azure subscriptions without APIM are skipped, inventory covers all design item 2 resources via allow-list projection, only GET calls, Note yields boolean only and Note content never appears in outputs, non-empty Note reports Full Name/Email/State/Identity/Groups

### Task 5: Tests for approvals and key rotation
- Track: test
- Covers: AC1, AC4, AC8, AC9, AC11
- Files: APIManagementServices/tests/Rotation.Tests.ps1, APIManagementServices/tests/Approval.Tests.ps1
- Depends on: 1, 2
- Verifiable by: tests assert -RotateKey Primary/Secondary/All calls the right regenerate endpoints, only active subscriptions, no call without service approval, master needs separate confirmation and its prompt contains the verbatim Microsoft warning, -WhatIf/-Confirm never bypass approvals, every approval/rejection logs a decision row, rejection does not stop the run

### Task 6: Tests for report, audit log, summary and exit code
- Track: test
- Covers: AC6, AC7, AC8, AC10, AC11
- Files: APIManagementServices/tests/Reporting.Tests.ps1
- Depends on: 1, 2
- Verifiable by: tests assert folder reports/<yyyyMMdd-HHmmss>/, <service>.md with "Decisions and outcomes", rotation-log.csv with the 12 columns, incremental rows, simulated marking under -WhatIf, no key values or Note content in any output, summary printed, exit code 0 only when no failure

### Task 7: Tests for main flow (mocked end to end)
- Track: test
- Covers: AC3, AC4, AC8, AC9, AC11
- Files: APIManagementServices/tests/MainFlow.Tests.ps1
- Depends on: 1, 2
- Verifiable by: tests assert service-at-a-time loop, continue-on-reject (D8) and continue-on-failure, "continue?" prompt, -WhatIf makes zero regenerate calls, leak scan of all outputs finds no key value or Note content, exit code 1 on any failure

### Task 8: Implement REST wrapper
- Track: code
- Covers: AC6, AC8, AC10
- Files: APIManagementServices/Invoke-ApimKeyRotation.ps1
- Depends on: 1, 3, 4, 5, 6, 7
- Verifiable by: Task 3 tests pass

### Task 9: Implement discovery, inventory and Note check
- Track: code
- Covers: AC2, AC3, AC5, AC6
- Files: APIManagementServices/Invoke-ApimKeyRotation.ps1
- Depends on: 4, 5, 6, 7, 8
- Verifiable by: Task 4 tests pass

### Task 10: Implement audit log and service report
- Track: code
- Covers: AC6, AC7, AC10, AC11
- Files: APIManagementServices/Invoke-ApimKeyRotation.ps1
- Depends on: 4, 5, 6, 7, 9
- Verifiable by: Task 6 report/log tests pass

### Task 11: Implement approvals and key rotation
- Track: code
- Covers: AC1, AC4, AC8, AC9, AC11
- Files: APIManagementServices/Invoke-ApimKeyRotation.ps1
- Depends on: 5, 8, 10
- Verifiable by: Task 5 tests pass

### Task 12: Implement main flow, summary, exit code
- Track: code
- Covers: AC3, AC4, AC8, AC9, AC11
- Files: APIManagementServices/Invoke-ApimKeyRotation.ps1
- Depends on: 7, 9, 10, 11
- Verifiable by: Task 7 and Task 6 summary/exit tests pass; full suite green; a -WhatIf run against a non-production APIM (operator step) makes no change

### Parallelisation
- Group A (parallel): tasks 3, 4, 5, 6, 7 — disjoint test files, no mutual dependency (repo is not git: worktrees likely not applicable, run serially if preferred)
- Serial: tasks 1, 2 (first); tasks 8, 9, 10, 11, 12 (all edit the single script file)
- Spec writes: always serialised

## Implementation

| Task | Files | Status |
|---|---|---|
| 1 (Blocker: skeleton) | APIManagementServices/Invoke-ApimKeyRotation.ps1 | done |
| 8 | APIManagementServices/Invoke-ApimKeyRotation.ps1 | done |
| 9 | APIManagementServices/Invoke-ApimKeyRotation.ps1 | done |
| 10 | APIManagementServices/Invoke-ApimKeyRotation.ps1 | done |
| 11 | APIManagementServices/Invoke-ApimKeyRotation.ps1 | done |
| 12 | APIManagementServices/Invoke-ApimKeyRotation.ps1 | done |

Code track, round 1 loop 1/3. Only the single production file was changed; no test touched. validate-code (applied by reading the skill): no findings (no skeleton left, no dead code, no listSecrets/listValue/token path, no key/Note retained). Mocked Pester run (6.2.0 from temp copy, nothing real reachable): 70 pass / 7 fail. The Azure/APIM was never called, no script run.

### Remaining failures: 7, all caused by test defects (cannot be fixed in production code)
- Inventory.Tests.ps1 (4 tests: services discovered, allow-listed metadata 'Client One', Note user reported, Note user fields): the `Invoke-ApimRequest` mock uses `switch -Wildcard` with `'/subscriptions?*'` and `'*/subscriptions?*'`. In wildcard syntax `?` matches any single character, and every APIM path starts with / contains `/subscriptions/<id>/`, so every request is answered by the first matching branch (Azure subscription list / APIM subscription list); the service, users, groups branches are unreachable. Fix needed in the test mock (anchor on the query string, e.g. match `*/subscriptions\?*` via `-match`/regex or order the specific branches first).
- Reporting.Tests.ps1 (3 tests: two rows added, `=` injection guard, decision row stored): the tests share `$TestDrive/rotation-log.csv` across tests (Describe-level TestDrive, no cleanup) so earlier rows remain. Each passes when run alone (verified). Fix: delete the log in BeforeEach or use a unique file per test.

### Deviations from plan
- `Get-ApimInventory` also embeds the `Test-UserNotes` result (`Notes`) so the report can list non-empty-Note users; the inventory requests `/users`.
- Result/Outcome text is reduced to a fixed vocabulary (`ConvertTo-SafeResult`, e.g. `failed (HTTP 500)`, `rotated`) before it reaches the CSV, report or summary, so a secret echoed in an error can never be persisted.
- Added helpers: `Get-UtcTimestamp`, `Get-SignedInIdentity`, `Get-RetryDelaySeconds`, `Send-ApimRequest`, `Get-ApimPath`, `Initialize-RotationLog`, `Register-Decision`, `Read-Approval`, `ConvertTo-MdCell`.
- On service rejection the main flow also writes an `EventType=skip, Decision=rejected` row (needed by the MainFlow test where `Confirm-ServiceRotation` is mocked; the real `Confirm-ServiceRotation` already logs its own decision row).
- File writes use `-WhatIf:$false -Confirm:$false` so reports and the audit log are still written under `-WhatIf` (only regenerate calls are simulated).
- A POST ending without any response is never retried (`outcome unknown`); 5xx on POST is retried as the tests require (ADR-004 wording about ambiguous POST kept for no-response case).
- Script-invoked exit code: `exit` with the main flow return value; `-RotateKey` presence enforced inside the main flow (not `Mandatory`, see skeleton deviation).

### Deviations from plan
- `-RotateKey` is declared with ValidateSet but not `Mandatory` in the skeleton — a Mandatory parameter would prompt when the script is dot-sourced by tests; task 12 enforces it in the main flow.
- Extra stub functions beyond the listed ones: `Get-ApimServices`, `Write-RotationSummary`, `Invoke-ApimKeyRotationMain`; approval helpers named `Confirm-ServiceRotation` / `Confirm-MasterRotation`.
- Dot-source guard (`InvocationName -ne '.'`) runs the main stub only when invoked as a script.
- Blocker run only: no other code task done; spec status unchanged (planned).

## Test Implementation

Pester 6.2.0, files under `APIManagementServices/tests/` (T = that folder). HARD SAFETY RULE applied: `T/TestSupport.ps1` shadows `Invoke-AzRestMethod`, `Connect-AzAccount`, `Get-AzContext`, `Set-AzContext`, `Get-AzSubscription`, `Get-AzAccessToken`, `Invoke-RestMethod`, `Invoke-WebRequest` and `Read-Host` with THROWING stubs (functions win over Az cmdlets, Az need not be absent); each test file re-mocks them and asserts zero real Azure calls. POSTs only reach the mocked `Invoke-ApimRequest`. The script itself is never run. Canary strings stand in for key values / Note content.
Red run (Pester 6.2.0 from a temp copy, no install): 77 tests, 4 pass (Preflight, expected), 73 fail: `NotImplementedException` from the skeleton (69) or assertion (4). No syntax failures. `red_confirmed: yes`.
Assumed contracts (for the code track): `Invoke-ApimKeyRotationMain` returns the exit code (0/1); `Confirm-*Rotation` return bool and log a decision row via `Add-RotationLogRow -Row <hashtable with the 12 CSV column names> -LogPath`; `Invoke-KeyRotation` returns result objects (Subscription, KeyRotated, Result) and asks `Confirm-MasterRotation` itself; `Get-ApimInventory` result is allow-list projected; `Test-UserNotes` returns `NonEmptyNoteUsers` (FullName, Email, State, Identity, Groups); wrapper error text for forbidden paths contains "forbidden", for ambiguous POST "outcome unknown", and includes HTTP status + path; the "continue?" prompt uses `Read-Host`.

| Spec reference | Location | Test | Cases | Status |
|---|---|---|---|---|
| D16 | Pester: T/Preflight.Tests.ps1 | Preflight.Given a required Pester version that is not installed When the runner pre-check runs Then it exits non-zero with a clear message; Given the installed Pester When the suite runs Then its version is at least 5 | all | written-after-code (runner in T/Invoke-Tests.ps1; passes) |
| AC1 | Pester: T/Rotation.Tests.ps1 | Invoke-KeyRotation.Given RotateKey Primary / Secondary / All When keys are rotated Then ... (3 tests) | all | red |
| AC2 | Pester: T/Inventory.Tests.ps1 | Given an APIM service When the inventory is taken Then only GET requests are made; Given providers that carry client secrets ... no secret value or secret field | all | red |
| AC3 | Pester: T/Inventory.Tests.ps1, T/MainFlow.Tests.ps1 | Given an Azure subscription without APIM ... skipped; Given several Azure subscriptions ... enumerated; Given two services both approved ... one service at a time | all | red |
| AC4 | Pester: T/Approval.Tests.ps1, T/MainFlow.Tests.ps1 | Given the user answers no ... rejected; Given an unrecognised or empty answer ... rejection; Given no service approval ... no regenerate call; Given the first service rejected ... next service is still processed | all | red |
| AC5 | Pester: T/Inventory.Tests.ps1 | Given an APIM service When the inventory is taken Then every design resource family is requested; Given one user with a Note and one without ...; Given a user with a non-empty Note ... Full Name, Email, State, Identity and Groups; Given a user with a Note ... no Note property | all | red |
| AC6 | Pester: T/Inventory, Reporting, Rotation, Invoke-ApimRequest, MainFlow .Tests.ps1 | Given subscriptions that carry keys ... only allow-listed metadata remains; Given an error response echoing a key value ...; Given a row that wrongly carries a key value ...; Given an inventory and results that carry key and Note canaries ...; Given subscriptions with keys and users with Notes ... no key value or Note content appears; and the Rotation/summary leak tests | all | red |
| AC7 | Pester: T/Reporting.Tests.ps1, T/Rotation.Tests.ps1 | Given rotated, failed, simulated and skipped results When the report is written Then each subscription, key and result is stated; Given every regeneration ... an action row ... is logged | all | red |
| AC8 | Pester: T/Invoke-ApimRequest, Rotation, MainFlow, Reporting .Tests.ps1 | 429/503 retry tests; Retry-After; 404 not retried; ambiguous POST not retried; Given WhatIf ... no regenerate call (Rotation and MainFlow); failure-continues tests; summary counts; exit code 1 / 0 tests | all | red |
| AC9 | Pester: T/Rotation.Tests.ps1, T/Approval.Tests.ps1 | Given suspended and cancelled ... never rotated; Given the master subscription not confirmed / confirmed ...; Given automatic confirmation requested with Confirm false ... still asked; Given the user answers yes When the master rotation is asked Then the prompt shows the Microsoft all-access warning verbatim | all | red |
| AC10 | Pester: T/Invoke-ApimRequest, MainFlow, Reporting .Tests.ps1 | Given a path without api-version ... 2024-05-01; Given a run When it starts Then a timestamped folder with the audit CSV and one report per processed service is created; Given a log row When it is added Then the CSV is created with the 12 columns | all | red |
| AC11 | Pester: T/Approval, Reporting, MainFlow .Tests.ps1 | Given an approval / a rejection ... decision row is logged; Given a master approval and a master rejection ...; Given a decision row When it is added ...; Given a rejection When the flow runs Then the decision is recorded in the audit CSV; Given a processed service ... Decisions and outcomes section | all | red |

### Skipped for safety (user tests manually on a no-impact development APIM service)
- skipped-for-safety: any real `-WhatIf` or real run against Azure/APIM (Success criteria "verifiable on a non-production APIM", Task 12 operator step). Not automated; no Pester test touches Azure.
- skipped-for-safety: Developer Portal key retrieval, real 429/5xx behaviour of the service, real Az login/identity (`Get-AzContext`) — manual only.
- Not testable in Pester: "Note content discarded from memory right after the check" (AC10/D13); only its observable effect (no Note content in results, output, files) is asserted.

### Rounds
- Round 1, loop 1/3.

## Test Results

Round 1, loop 1/3. Pester 6.2.0 (temp copy), fully mocked (TestSupport.ps1 throwing stubs verified before running). Full output: `execution-log.md`.

- Total: 77 | Passed: 70 | Failed: 7 | Skipped: 0

| Test | Spec reference | Result | Diagnosis |
|---|---|---|---|
| Inventory: Given an Azure subscription without APIM ... only the APIM service is returned | AC3 | fail | test-error (mock wildcard `/subscriptions?*` also matches `/subscriptions/...`) |
| Inventory: Given subscriptions that carry keys ... only allow-listed metadata remains | AC6 | fail | test-error (same mock) |
| Inventory: Given one user with a Note and one without ... only the user with a Note is reported | AC5 | fail | test-error (same mock) |
| Inventory: Given a user with a non-empty Note ... Full Name, Email, State, Identity and Groups | AC5 | fail | test-error (same mock) |
| Reporting: Given two rows added one after the other ... both are present | AC7 | fail | test-error (shared $TestDrive CSV not cleaned) |
| Reporting: Given a value starting with an equals sign ... prefixed | AC6 | fail | test-error (shared CSV, row [0] is from an earlier test) |
| Reporting: Given a decision row When it is added ... stored | AC11 | fail | test-error (shared CSV, row [0] is from an earlier test) |

Implementer's diagnosis confirmed independently: 0 implementation-error, 7 test-error, 0 regression, 0 flaky, 0 stale-mapping.

Round 1, loop 2/3 (after Inventory.Tests.ps1 and Reporting.Tests.ps1 fixes). Pester 6.2.0 (temp copy), fully mocked, throwing stubs in TestSupport.ps1 confirmed first; no Azure/APIM call. Full output: `execution-log.md`.

- Total: 77 | Passed: 77 | Failed: 0 | Skipped: 0
- Diagnoses: 0 failures; 0 stale-mapping (every traceability-table test file ran). all_green: yes.

## Verification

| Check | Result | Detail |
|---|---|---|
| Spec contract | pass | AC1-AC11 + D16 traced to tests; 77/77 green; tasks done |
| Coverage | not-configured | no tool/bar declared; informational 89.5% commands (620/693) |
| Lint | not-configured | no linter configured or installed |
| Security | not-configured | manual checks only, 0 findings; no secret scanner/SAST |

Detail: `verification-report.md`.

### Failure analysis
- None. Coverage, lint and security tooling could not run (not-configured); awaiting recording of user risk acceptance.

## Status History

| Date | Status | By |
|---|---|---|
| 2026-11-24 | draft | create-spec-from-jira |
| 2026-11-24 | decisions_closed | sdd-decision-maker |
| 2026-11-24 | designed | sdd-designer |
| 2026-11-24 | designed (documentation clarification: master = APIM built-in all-access subscription; verbatim warning in master prompt) | sdd-designer |
| 2026-11-24 | designed (design addition: D14 no unattended mode, D15 decision audit/AC11, D16 Pester 6.2.0; ADR-003/005 amended) | sdd-designer |
| 2026-11-24 | planned | sdd-planner |
| 2026-11-24 | implemented_test | sdd-coding-testing-implementer |
| 2026-11-24 | implemented_code | sdd-coding-implementer |
| 2026-11-24 | implemented_done | sdd-coding-testing-tester |


## Testing fixes

Changes made while testing the script against real Azure:

1. **PowerShell 7 required** – `#Requires -Version 7.0` fails in Windows PowerShell 5.1. Run with `pwsh`.
2. **Usage message** – running without `-RotateKey` prints usage (parameters `-RotateKey`, `-OutputRoot`, `-WhatIf`, with a `-WhatIf` example) and exits with code 1 instead of throwing.
3. **Azure sign-in** – after parameter validation, the script runs `Connect-AzAccount` (browser sign-in, `-WhatIf:$false -Confirm:$false -ErrorAction Stop`) and `Get-AzAccessToken | Out-Null`, before any other action. `-WhatIf` still needs authentication for read-only calls.
4. **Interactive subscription picker** – replaces the temporary single-subscription restriction (used only for early testing and fully removed). New `Get-AzureSubscriptionList` and `Select-AzureSubscription` (numbered list, `Q` to finish, re-prompt on invalid input); `Get-ApimServices` takes a mandatory `-SubscriptionId`. After each subscription the user is asked whether to select another; summary and exit code are aggregated, with one report folder per run.
5. **Empty subscription ID bug** – "No APIM services found in accessible Azure subscription ." came from an undefined variable; removed with the picker.
6. **Tests** – updated `MainFlow`, `Inventory`, `Preflight` tests and `TestSupport` stubs (picker flow, usage exit, sign-in mocks, three `Select-AzureSubscription` tests). Test data uses neutral placeholder GUIDs. Pester 5+ is required to run them.
