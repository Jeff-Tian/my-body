# Work Routing

How to decide who handles what.

## Routing Table

| Work Type | Route To | Examples |
|-----------|----------|----------|
| App architecture, data flow, scope calls | Ripley | Module boundaries, persistence strategy, sync approach |
| SwiftUI / UI / navigation / accessibility | Lambert | Photo picker screen, review/edit screen, permission prompts |
| Vision / OCR / InBody parsing | Ash | Extract text from image, parse fields, handle units |
| HealthKit writes & authorization | Ash | Request permissions, write samples, dedupe |
| CloudKit / iCloud sync | Ash | Private DB schema, conflict resolution, KV store |
| Tests, fixtures, regression | Parker | XCTest, UI tests, OCR golden fixtures |
| Well-scoped autonomous issues | @copilot | UI tweaks, bug fixes with clear repro, docs — see capability profile in team.md |
| Code review | Ripley | Review PRs, check quality, suggest improvements |
| Secrets / Apple Developer / App Store Connect / signing / cloud / release manual ops | 👤 Jeff Tian | Key material, provisioning profiles, certificates, App Store Connect, cloud/infra consoles, production release steps |
| Scope & priorities | Ripley (proposes) → 👤 Jeff Tian (decides) | What to build next, trade-offs, release priorities |
| Session logging | Scribe | Automatic — never needs routing |
| Work queue / backlog monitoring | Ralph | Triage issues, drive backlog, idle-watch |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:{member}` label | Lead |
| `squad:{name}` | Pick up issue and complete the work | Named member |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, the **Lead** triages it — analyzing content, assigning the right `squad:{member}` label, and commenting with triage notes.
2. When a `squad:{member}` label is applied, that member picks up the issue in their next session.
3. Members can reassign by removing their label and adding another member's label.
4. The `squad` label is the "inbox" — untriaged issues waiting for Lead review.

## Rules

1. **Eager by default** — spawn all agents who could usefully start work, including anticipatory downstream work.
2. **Scribe always runs** after substantial work, always as `mode: "background"`. Never blocks.
3. **Quick facts → coordinator answers directly.** Don't spawn an agent for "what port does the server run on?"
4. **When two agents could handle it**, pick the one whose domain is the primary concern.
5. **"Team, ..." → fan-out.** Spawn all relevant agents in parallel as `mode: "background"`.
6. **Anticipate downstream work.** If a feature is being built, spawn the tester to write test cases from requirements simultaneously.
7. **Issue-labeled work** — when a `squad:{member}` label is applied to an issue, route to that member. The Lead handles all `squad` (base label) triage.
8. **Human handoffs** — when work routes to 👤 Jeff Tian (secrets, Apple Developer/App Store Connect, signing/provisioning, cloud/infra consoles, production/release manual operations), pause and surface a clear task; he relays results back through the user.
