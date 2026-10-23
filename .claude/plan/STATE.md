# STATE

STATUS: PENDING
<!-- PENDING | RUNNING | DONE | BLOCKED -->

M2 — On-device AI, suggestions, optional endpoints. Spec: `.claude/plan/PHASES.md`.
Source docs: `docs/EXECUTION_PLAN.md` §7, `legal/data-map.yaml`, `legal/assessment.md`.
9 phases (P1–P9), one commit each. Ends with internal snapshot v0.0.2.

M1 is **code complete, release pending** (user decision, 2026-10-23): its plan and handoff log are in
`.claude/plan/archive/`; v0.1.0 is finished on branch `release/0.1` (iCloud entitlement, generated legal
documents, `PrivacyInfo.xcprivacy`, device exit test) when the membership, the lawyer and the iPhone are
available (3–4 weeks).

## Roadmap

| # | Milestone | Execution plan | Status |
|---|---|---|---|
| M1 | Standalone MVP | §1–§6, §9, §10 | code complete, v0.0.1 snapshot; v0.1.0 pending on `release/0.1` |
| M2 | On-device AI and optional endpoints (Ollama, Claude, OpenAI) | §7 | cut 2026-10-23 |
| M3 | Import (share extension, mail) and direct cloud APIs | §6 | planned |
| M4 | fin connector, sign-in with fin credentials (ADR 0003) | §8 | planned |
| M5 | Release polish, App Store decision | — | planned |

## Preconditions

- [x] M1 code complete, gate green on the Mac (2026-10-23)
- [x] Apple Intelligence available on the user's Mac for P2's manual check (user, 2026-10-23)
- [ ] API keys for the by-hand checks of P6–P8 (Claude, OpenAI) and an Ollama server: only the MANUAL
      steps need them; the gates never do

## Contract

Passed verbatim to every `etzian:phase-runner` subagent. Repo rules also apply: `.claude/rules/`.

- Repo root: `.` · `SlipsCore/` Swift package (no UI imports) · `Slips/` app target · iPhone only, iOS 18+, Swift 6
- Foundation: `~/etzian/_foundation`; ADR 0001's table says how each layer applies; Swift rules in `.claude/rules/swift.md`
- Gate: `./scripts/gate.sh` (redirect to a file, read the tail). Simulator: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
- Storage: GRDB, append-only migrations (`v1_initial`, `v2_fts`, next `v3_…`); amounts in minor units + currency; UUID ids made on device
- Sub-category keys mirror `../fin/packages/shared/src/categories.ts`; kinds `personal`, `family`, `enterprise` (+ `any`)
- Every delivery goes through `deliveries`; capture never waits on the network or on a model; retries are idempotent
- **AI:** the parser is the source of each field; an assistant fills gaps and raises checks, never
  overwrites what the user typed. On-device model on by default when available. Endpoints (Ollama,
  Claude, OpenAI) are off by default, per profile, and send nothing without stored consent; only OCR text
  with card digits masked, never the image. Every model behind a protocol with a fake; no gate calls a
  model, a LAN host or the internet
- Strings in `Localizable.xcstrings`, `en` + `fr-CA` in the same commit; Québec terms; product name never in a sentence
- Colours and spacing from `EZ.*` tokens (managed copy, never edited); SF + Dynamic Type; 44 pt targets
- Company facts only from `Slips/Generated/Company.swift`; bundle id `com.etzian.slips`
- No real slip, card number or registration number anywhere in the repo; fixtures are synthetic text
- No user-derived value in logs (`privacy: .private`); secrets (WebDAV passwords, API keys) in the Keychain only
- No new dependency without naming its licence and asking (providers are plain HTTPS: no SDK)
- No Apple Developer Program membership yet: no new entitlement in M2
- One commit per phase: `feat(m2): P<n> <slice>`; the orchestrator commits

### Locked decisions from M1

- UUIDs are GRDB 16-byte blobs; `txn_date` is `CalendarDay` (`YYYY-MM-DD`); records conform to `SlipsRecord` (snake_case).
- `slips.extracted` = `Extraction` JSON, `slips.checks` = `[Check]` JSON recomputed on every save; check messages are `check.<code>` with `%@` values.
- `DestinationAdapter` protocol; outbox claims rows with a conditional UPDATE, backoff 30 s…6 h, `failed` at 20; `exists` compares SHA-256.
- `HTTPTransport` is the seam for every HTTP client (WebDAV now, AI providers next); plain HTTP only for hosts marked local, with a warning.
- Screens observe through `SlipsCore` streams, never GRDB; catalog keys are dotted identifiers, `extractionState: manual`.
- `-uiTesting` = in-memory database, first run skipped; UI tests pin English and a standard text size.
- `LibraryEntry` (not `LibraryItem`) and `SlipsCore.NormalizedRect`: Apple frameworks own those names.

## Phases

| # | Slice | Status |
|---|---|---|
| P1 | AI seam in core: assistant protocol, merge, disagreement checks | pending |
| P2 | On-device Foundation Models adapter, on by default | pending |
| P3 | Suggestions from history improved | pending |
| P4 | Endpoint settings, consent, masking, data map | pending |
| P5 | Ollama adapter (LAN) | pending |
| P6 | Claude API adapter | pending |
| P7 | OpenAI (ChatGPT) API adapter | pending |
| P8 | Evaluation harness and model choice | pending |
| P9 | Polish: fr-CA parity, docs, legal assessment, v0.0.2 | pending |

## Handoff log
