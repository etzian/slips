# Plan — M2 On-device AI, suggestions, optional endpoints — 9 phases (P1–P9)

Spec file. Never edited by the loop. Every phase ends in a gate that exits 0/non-zero.

Source docs (read before any phase):
- `docs/EXECUTION_PLAN.md` §7 (AI), §3 (data model), §5 (checks), §9 (privacy).
- `legal/data-map.yaml`, `legal/assessment.md`.
- `.claude/rules/swift.md` for every Swift source; `.claude/plan/STATE.md` — Contract + Handoff log.
- M1's plan and decisions: `.claude/plan/archive/`.

Milestone in one line: the phone proofreads every slip with an on-device model and suggests its
classification better; a user who wants it can point a profile at their own Ollama server, the Claude
API or the OpenAI API, and nothing is sent until they consent to exactly what is sent.

Exit test:
- `./scripts/gate.sh` passes. No gate needs Apple Intelligence, a LAN host or the internet: every model
  sits behind a protocol with a fake in the tests.
- On the Mac (Apple Intelligence on) and later the iPhone, by hand: a slip whose parser and model
  disagree shows the disagreement as a check; with the model unavailable the app behaves exactly like M1.
- Endpoint off or not consented: no request leaves the phone (a test asserts the transport is never
  called). Endpoint on: only the OCR text with card digits masked is sent, never the image.
- Consent withdrawn in one tap: provider off, key forgotten.

Execution model: one commit per phase on the main line (`m1-standalone-mvp` branch until the user
renames it), message `feat(m2): P<n> <slice>`. Internal snapshot `v0.0.2` at the end. M2's public
release (`v0.2.0`) comes after `v0.1.0` and needs the legal review of `features.ai_processing`.

## Model per phase

| # | Slice | Model | Size |
|---|---|---|---|
| P1 | AI seam in core: assistant protocol, merge, disagreement checks | sonnet | M |
| P2 | On-device Foundation Models adapter, on by default | sonnet | M |
| P3 | Suggestions from history improved | sonnet | M |
| P4 | Endpoint settings, consent, masking, data map | opus | M |
| P5 | Ollama adapter (LAN) | sonnet | S |
| P6 | Claude API adapter | sonnet | S |
| P7 | OpenAI (ChatGPT) API adapter | sonnet | S |
| P8 | Evaluation harness and model choice | sonnet | M |
| P9 | Polish: fr-CA parity, docs, legal assessment, v0.0.2 | sonnet | S |

## Gate commands (canonical)

`./scripts/gate.sh` as in M1 (swift test, xcodebuild build test, strings, hygiene, licences). No new
Swift package: providers are plain HTTPS through `HTTPTransport`; Foundation Models is an Apple framework.

## P1 — AI seam (core)

**Model:** sonnet. **Size:** M.

- `SlipsCore/Sources/SlipsCore/AI/`: `ExtractionAssistant` protocol (input: OCR text, locale, currency
  hint; output: `AIExtraction` with the fields of `Extraction`, each with a confidence, and a suggested
  sub-category key from fin's list); `AIResult` stored on the slip as JSON (migration `v3_ai`: column
  `slips.ai` TEXT, append-only).
- Merge policy: the parser stays the source; the assistant fills only fields the parser left empty or
  below `ExtractedField.lowConfidence`, marked AI-filled; never overwrites a value the user typed.
- Disagreement checks: `ai_disagrees_total` (warning), `ai_disagrees_date`, `_merchant`, `_taxes` (info),
  with values; part of `SlipChecks` through the context.
- `FakeAssistant` in tests.
- **Gate:** `./scripts/gate.sh`; tests: merge fills only gaps, user edits kept, each disagreement fires and
  does not fire, migration from v2.

## P2 — on-device model (app)

**Model:** sonnet. **Size:** M.

- `Slips/AI/OnDeviceAssistant.swift`: Foundation Models, availability checked at runtime
  (`SystemLanguageModel.default.availability`); `@Generable` output; prompt from OCR text only; timeout.
  Unavailable (older iOS, device not eligible, Apple Intelligence off, model not ready) = no assistant,
  silently, with the reason shown in Settings.
- Runs after OCR in the capture flow; the slip is already saved; the review screen updates when the
  result arrives (never blocks Save).
- Settings › Privacy: "Proofread with on-device AI", **on by default** (user, 2026-10-23: nothing leaves
  the phone); status line with availability.
- **Gate:** `./scripts/gate.sh`; unit tests for the prompt builder and the unavailable path. MANUAL: run a
  few synthetic slips on the Mac with Apple Intelligence and record what disagreed.

## P3 — suggestions from history

**Model:** sonnet. **Size:** M.

- Ranking per field: frequency and recency per normalised merchant (decay), payment-method
  co-occurrence, amount range; the assistant's sub-category key as the last source. Archived values
  never suggested.
- Review screen: a one-line "suggested because…" under a pre-filled picker.
- **Gate:** `./scripts/gate.sh`; ranking tests (ties, decay, archived, assistant fallback).

## P4 — endpoint settings and consent

**Model:** opus (consent and what leaves the phone). **Size:** M.

- Per profile, Settings › AI: Off (default) · Ollama on my network (URL) · Claude API (key) · OpenAI API
  (key). Keys in the Keychain by profile + provider.
- "What is sent" screen showing the real text of the current slip as it would be sent: OCR text only,
  card digits masked (`SlipsCore` masking function), no image, no notes, no names of profiles or
  businesses. Explicit consent stored per profile (provider, scope version, date); changing provider or
  scope asks again; withdraw = Off + key deleted.
- `AssistantRouter` in core: on-device first (P2), then the consented endpoint only when the user taps
  "Ask <provider>" on a slip, or automatically if they chose "every slip" in the consent.
- `legal/data-map.yaml`: `features.ai_processing`, the three recipients (Ollama: user's server; Anthropic
  and OpenAI: vendors outside Québec); `legal/assessment.md` §AI.
- **Gate:** `./scripts/gate.sh`; tests: nothing is sent while Off or without consent, masking (13–19 digit
  runs, masked cards, registration numbers kept), scope change re-asks.

## P5 — Ollama adapter

**Model:** sonnet. **Size:** S.

- `SlipsCore/AI/OllamaAssistant.swift` on `HTTPTransport`: `/api/chat` with a JSON schema (`format`),
  model chosen in settings, timeout; HTTPS unless the host is marked local (same rule and warning as
  WebDAV); probe for the settings screen.
- **Gate:** `./scripts/gate.sh`; tests against an in-process fake server (request body has no image and
  masked digits; malformed answers ignored).

## P6 — Claude API adapter

**Model:** sonnet. **Size:** S. Load the `claude-api` skill before writing it.

- `SlipsCore/AI/ClaudeAssistant.swift`: Messages API over `HTTPTransport`, structured output through a
  tool schema, the smallest current model that passes P8, the instructions prompt-cached; key from the
  Keychain; errors (401, 429, 5xx) mapped, never blocking a slip.
- **Gate:** `./scripts/gate.sh`; tests with a fake transport (headers, request shape, no image, masking,
  error mapping, cache-control on the instructions).

## P7 — OpenAI (ChatGPT) API adapter

**Model:** sonnet. **Size:** S.

- `SlipsCore/AI/OpenAIAssistant.swift`: Chat Completions or Responses API over `HTTPTransport`, JSON
  schema structured output, the smallest current model that passes P8; key from the Keychain; errors
  mapped.
- **Gate:** `./scripts/gate.sh`; tests with a fake transport as in P6.

## P8 — evaluation

**Model:** sonnet. **Size:** M.

- The OCR fixtures through each assistant: recorded responses in the tests; a by-hand script for live
  runs (`scripts/eval-ai.sh`, keys from the environment, never committed). Report: field accuracy vs the
  parser and vs the expected JSON; the model chosen for P6 and P7 with its numbers in `docs/AI.md`.
- **Gate:** `./scripts/gate.sh` (recorded responses only).

## P9 — polish

**Model:** sonnet. **Size:** S.

- fr-CA and en for every new string (Québec terms); `docs/AI.md` (what runs where, what is sent);
  `legal/assessment.md` and the data map final for M2; `CHANGELOG.md`; `MARKETING_VERSION` 0.0.2 and
  tag `v0.0.2` (internal snapshot, `.claude/rules/release.md`).
- **Gate:** `./scripts/gate.sh`, `ez doctor .`.
