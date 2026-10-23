# STATE

STATUS: RUNNING
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
| P1 | AI seam in core: assistant protocol, merge, disagreement checks | done |
| P2 | On-device Foundation Models adapter, on by default | done |
| P3 | Suggestions from history improved | done |
| P4 | Endpoint settings, consent, masking, data map | pending |
| P5 | Ollama adapter (LAN) | pending |
| P6 | Claude API adapter | pending |
| P7 | OpenAI (ChatGPT) API adapter | pending |
| P8 | Evaluation harness and model choice | pending |
| P9 | Polish: fr-CA parity, docs, legal assessment, v0.0.2 | pending |

## Handoff log

### P1 — AI seam · pass (Linux; Mac gate to confirm) · 2026-10-23 · commit d93d501

Gate steps 1, 3, 4, 5 exit 0 (138 core tests). No app source changed except the catalog.

- CHANGED: migration `v3_ai` (`slips.ai` TEXT); `Slip.ai` + `aiResult`; `SlipsCore/AI/ExtractionAssistant.swift`
  (`AssistantInput`, `AIExtraction`, `ExtractionAssistant`, `AIResult`, `AIMerge.merge`/`sanitized`);
  `SlipChecks` context `ai` + `ai_disagrees_total` (warning), `_date`, `_merchant`, `_taxes` (info);
  `SlipStore.recordAI`; `AITests.swift` (`FakeAssistant`); 4 catalog keys
- DECISIONS: A field is filled by the assistant only if the slip's value is empty, or equals the parser's reading and that reading is low-confidence; a value different from the parser's counts as typed by the user and is never touched. Filled field names are kept in `AIResult.filled`. On a filed (`ready`) slip the reading is stored and raises checks but fills nothing. `sanitized` drops sub-category keys outside `Seed.allKeys`, negative amounts and non-ISO currencies. Disagreement tolerances: total > 2 ¢ (warning), any tax > 1 ¢, date different, merchant names that neither contain the other after normalisation (info). The check shows the assistant's value; the slip's stands.
- DEFERRED: none
- MANUAL: none

### P2 — on-device model · pass (Mac gate green after fix c499b99) · 2026-10-23 · commit f147580

Gate steps 1, 3, 4, 5 exit 0 (143 core tests). App sources parse-checked only.

- CHANGED: core `AI/AssistantPrompt.swift` (shared instructions with fin's keys, user message, JSON schema,
  `AssistantReading` lenient decoding → `AIExtraction`) + tests; app `AI/OnDeviceAssistant.swift`
  (`OnDeviceAI` status/switch, `@Generable GeneratedSlipReading`, `OnDeviceAssistant`, `withTimeout`),
  capture runs it in the background after OCR (30 s limit) and `recordAI`s the result; review screen marks
  AI-filled fields (sparkles) and takes a result that arrives while it is open; Settings › Privacy › AI
  switch (on by default) with the availability reason; `SlipsTests/OnDeviceAITests.swift`; data map
  `automated_processing.ai_on_device`; 10 catalog keys
- DECISIONS: One prompt and one answer shape for every assistant (`AssistantPrompt.version` 1), amounts generated as text and converted in the core; model confidence fixed at 0.7. The model never delays the save: it starts after the review opens; failures and timeouts are logged privately and ignored. On the review screen a late result fills a field only if the user has not touched it since the screen loaded.
- DEFERRED: none
- MANUAL: on the Mac with Apple Intelligence on, run the simulator (macOS 26 shares the model with the simulator only if supported; otherwise "My Mac (Designed for iPhone)" or wait for the iPhone): import a few synthetic slips, check the sparkles and any `ai_disagrees_*` checks; turn the switch off and check nothing runs

### P3 — suggestions from history · pass (Linux; Mac gate to confirm) · 2026-10-23

Gate steps 1, 3, 4, 5 exit 0 (145 core tests). App sources parse-checked only.

- CHANGED: core `Classification/Suggestions.swift` (`HistoryEntry`, `Suggestion` with per-field
  `SuggestionReason`, tiered ranking), `SlipStore.suggestion` returns a `Suggestion` built from the
  profile's filed slips (last 1,000) and the AI's sub-category key; tests rewritten; review screen shows
  "suggested because…" under each pre-filled picker while it keeps the suggested value; 5 catalog keys
- DECISIONS: Tiers, best first, each field taking the first that gives an active value fitting the kind: card (payment method + its default kind/business) → same merchant (recency weight, half-life 90 days, majority by weight, tie to the most recent) → similar total ±25 % with the same payment method → most recent filed slip → AI key (sub-category only). History comes from filed (`ready`) slips, no longer from `merchant_memory` (still written; may be dropped later).
- DEFERRED: none
- MANUAL: none
