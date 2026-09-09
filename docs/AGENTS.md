# FoodPOS — Agentic Development System (Design Agent + Memory)

**Version:** 1.0 · **Date:** 2026-09-06

This document defines how AI agents work on FoodPOS: the agent roster, the
**Design Agent**, and the **memory system** that keeps any agent (or human)
continuity across sessions.

---

## 1. Agent Roster

| Agent | Trigger | Input | Output |
|-------|---------|-------|--------|
| **Review Agent** | "review" / start of any phase | Source paths | Findings ledger (file:line, severity, fix) → `memory/findings/` |
| **Design Agent** | Before building any feature/endpoint/table | One PRD slice + existing schema | Design Brief → `memory/design/` |
| **Build Agent** | After a Design Brief exists | Brief + phase task list | Code + tests, PR-style diff summary |
| **Verify Agent** | After each build task | Diff + test commands | Green/red report; blocks phase exit on red |
| **Release Agent** | Phase exit | Verified task list | Changelog entry + phase report in `memory/phases/` |

All agents read/write only inside this repo. Agents never bypass the Verify
Agent's gates.

## 2. The Design Agent

The Design Agent turns a PRD slice into an implementation-ready brief **before**
any code is written. It is the only agent allowed to change schema or API
contracts (changes must append to `memory/design/decisions.md`).

### 2.1 Inputs
1. The relevant PRD section (`docs/PRD.md`)
2. Current schema (`docs/ARCHITECTURE.md` §3) and API surface (§4)
3. Open questions from `memory/design/open-questions.md`

### 2.2 Mandatory outputs (one file per design)
`memory/design/DB-<slug>.md` with the fixed template:

```markdown
# Design Brief: <feature>
- PRD ref: FR-XX
- Status: draft | approved | implemented
## Contracts
- Tables changed/added (DDL sketch)
- Endpoints (method, path, request, response, errors)
- WS events emitted
- State-machine transitions touched
## Invariants (testable)
- I1: <one assertable rule, e.g. "discount clamps to [0, subtotal]")
- I2: ...
## Money
- Every field: paise int / computed / display-only
## Edge cases
- <list each with expected behavior>
## Test plan
- Unit: <invariants> · Integration: <endpoint flows>
## Open questions
- <blocking questions → also append to open-questions.md>
```

### 2.3 Design Agent rules
1. **Money in paise** — any brief that introduces float money is rejected.
2. **No silent fallbacks** — a null must be visible (`"—"`, empty state), never
   fabricated ("Rahul", ₹5000). This was the #1 bug class in the v0 review.
3. **Single source of truth** — computed money lives in exactly one layer
   (Go service), never re-derived in UI.
4. **State machines** — any status field gets an explicit transition table;
   illegal transitions return 409.
5. **Offline-first** — every write design names its idempotency key.
6. **Reuse before invent** — check existing tables/endpoints first; extensions
   beat new tables.

## 3. Memory System

Memory is **files in the repo** (versioned, reviewable, agent-readable).
Directory contract:

```
memory/
├── PROJECT_STATE.md        # ← THE anchor: what exists, what's next (see §3.1)
├── decisions.md            # ADR-style log: decision, date, why, alternatives
├── open-questions.md       # unresolved questions + owner + blocking phase
├── findings/               # Review Agent ledgers: YYYY-MM-DD-<area>.md
├── design/                 # Design Agent briefs (DB-<slug>.md)
├── phases/                 # per-phase reports: plan, done, learnings
└── glossary.md             # domain terms (KOT, Z-report, outbox, ...)
```

### 3.1 `PROJECT_STATE.md` (read first, always)
Fixed sections, updated by Release Agent at phase exit and Build Agent per task:

```markdown
# Project State (updated: <date>)
## Now
<one paragraph: current phase, active task, blockers>
## Done
- [x] Phase list with one-line result each
## Next (ordered)
1. <next task + design brief link>
## Verified commands
- backend: cd backend && go test ./... && go build ./...
- flutter: flutter analyze && flutter test
## Gotchas (hard-won)
- <one-liners that cost time to learn>
```

### 3.2 Memory rules for all agents
1. **Session start:** read `PROJECT_STATE.md` → relevant phase report → open
   questions. Never assume; if missing, write the question.
2. **Session end:** update `PROJECT_STATE.md` (Now/Next) and append learnings
   to the phase report. An unrecorded learning is a repeat bug.
3. **Findings ledger:** every review writes `memory/findings/<date>-<area>.md`
   with `status: open|fixed|wontfix` per item. Fixes reference finding IDs.
4. **Decisions are append-only.** To reverse one, add a new entry superseding it.
5. **Glossary:** introduce any new domain term there before using it in code/docs.

## 4. Working Protocol (per task)

```
Review (if needed) → Design Brief → Build → Verify → Memory update
     │                  │            │        │          │
 findings/         design/        code+    test       PROJECT_STATE.md,
 (open items)      DB-<slug>.md   tests    report     phases report,
                                                     decisions.md (if any)
```

- A task is **done** only when: code + tests + green verify + memory updated.
- Verify gates for backend: `go vet ./... && go test ./... && go build ./...`
- Verify gates for frontend: `flutter analyze` (0 errors) + `flutter test`.

## 5. Agent Guardrails

- Never edit generated/platform dirs (`android/`, `ios/`, `windows/`, `build/`).
- Never store secrets in repo; config via env.
- Never migrate data destructively without a superseding decision entry.
- Never introduce a dependency without: why, alternative considered, and a
  line in `decisions.md`.
