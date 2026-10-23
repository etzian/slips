# M2 draft — on-device AI, better suggestions, optional endpoint

**Draft for the user's approval.** Once approved, `etzian:plan-milestone` turns it into `PHASES.md` +
`STATE.md` (M1's plan is archived to `.claude/plan/archive/` as it stands: code complete, release
items carried on `release/0.1`). Source: `docs/EXECUTION_PLAN.md` §7.

Goal in one line: the phone proofreads every slip with an on-device model and suggests its
classification better; a user who wants it can point a profile at their own Ollama server or the Claude
API, with nothing sent until they consent to exactly what is sent.

Exit test:
- `./scripts/gate.sh` green on the Mac. No gate needs Apple Intelligence, a LAN host or the internet:
  every model is behind a protocol with a fake in the tests.
- On a Mac or iPhone with Apple Intelligence (by hand): a slip whose parser and model disagree shows the
  disagreement as a check; with the model unavailable the app behaves exactly like M1.
- Endpoint off: no request leaves the phone (a test asserts the transport is never called).
- Endpoint on: only the OCR text is sent (never the image, never a card number), after consent; consent
  can be withdrawn in one tap.

Release: internal snapshots `v0.0.x` while M2 is built. M2's public release (`v0.2.0`) comes after
`v0.1.0` and needs the legal review of `features.ai_processing` (Law 25 automated processing; transfer
outside Québec for a cloud provider).

## Phases

| # | Slice | Model | Needs |
| --- | --- | --- | --- |
| P1 | AI seam in core: `ExtractionAssistant` protocol, merge policy, disagreement checks | sonnet | — |
| P2 | On-device Foundation Models adapter + Settings toggle | sonnet | Apple Intelligence only for the manual check |
| P3 | Suggestions from history improved | sonnet | — |
| P4 | Endpoint settings and consent (no network yet) + data map | opus | — (legal review before release) |
| P5 | Ollama adapter (LAN) | sonnet | — |
| P6 | Claude API adapter | sonnet | an API key for the manual check |
| P7 | Evaluation harness and model choice | sonnet | — |
| P8 | Polish: fr-CA parity, legal assessment §AI, docs, `v0.0.2` | sonnet | — |

### P1 — AI seam (core)
- `ExtractionAssistant` protocol: input OCR text (+ locale, currency hint), output `AIExtraction` (the
  same fields as `Extraction`, each with a confidence, plus a suggested sub-category key).
- Merge policy: the parser stays the source of each field; the assistant fills only fields the parser
  left empty or low-confidence, marked as AI-filled; never overwrites a value the user typed.
- Disagreement checks (`ai_disagrees_total`, `_date`, `_merchant`, `_taxes`): info, warning for total.
- `FakeAssistant` in tests; parser fixtures run through the merge.
- Gate: `./scripts/gate.sh`; tests for merge, user edits kept, each disagreement both ways.

### P2 — on-device model (app)
- Foundation Models adapter: availability checked at runtime; `@Generable` struct; the OCR text only;
  timeout; runs after OCR and never delays the save (capture never waits).
- Settings › Privacy: "Proofread with on-device AI" (on when available; nothing leaves the phone).
- Gate: unit tests of the availability-off path and of the prompt builder; manual check on an Apple
  Intelligence device listed for the user.

### P3 — suggestions from history
- Rank by frequency and recency per merchant, payment method co-occurrence, amount range; the
  assistant's sub-category key as the last source; "why this suggestion" in the review screen.
- Gate: ranking tests (ties, decay, archived values ignored).

### P4 — endpoint settings and consent
- Per profile: Off (default) · Ollama on my network (URL) · Claude API (key in the Keychain).
- "What is sent" screen with the real text of the current slip, card digits masked; explicit consent
  stored (profile, provider, scope version, date); withdraw = off + forget the key.
- `legal/data-map.yaml`: `features.ai_processing`, recipients; `legal/assessment.md` updated.
- Gate: tests that nothing is sent while off or without consent, and that card digits are masked.

### P5 — Ollama adapter
- `HTTPTransport`-based client (like WebDAV): `/api/chat` with a JSON schema, LAN-only rules as WebDAV
  (HTTPS unless marked local), probe, timeout; errors never block a slip.
- Gate: tests against an in-process fake server.

### P6 — Claude API adapter
- Messages API with structured output (a tool schema), the smallest current model that passes P7,
  prompt caching for the instructions; key in the Keychain; `etzian:legal-compliance` notes the vendor.
- Gate: tests with a fake transport (request shape, no image, masking, error mapping).

### P7 — evaluation
- The OCR fixtures run through each assistant (recorded responses in tests; live runs by hand), a
  report of field accuracy vs the parser; the model choice for P6 recorded with its numbers.

### P8 — polish
- fr-CA and en for every new string; docs (`docs/AI.md`); `CHANGELOG.md`; `v0.0.2` snapshot.

## Questions for the user

1. Does your Mac support Apple Intelligence (Apple silicon, macOS 26, Apple Intelligence turned on)? If
   not, P2's manual check waits for the iPhone.
2. Both endpoint providers in M2 (Ollama and Claude), or only one first?
3. On-device AI on by default when available (nothing leaves the phone), or off until turned on?
