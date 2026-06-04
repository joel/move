# Phase D4 — Capture Image & Recognition Pipeline

**Release tag:** `ui-04`
**Branch:** `feature/ui-04-capture`
**Design status:** ✅ Design complete
**Depends on:** D0, D1, D2, D3
**Domain backing:** `prompts/Phase 04` (media upload) + `prompts/Phase 05` (recognition pipeline). Domain Spec §4.9–4.11, §5.3, §6; Technical Foundation §10; Design Spec §4 B2.

---

## 1. Goal
Deliver the image-only capture surface with unmistakable capture-to-box clarity, plus the provider-agnostic recognition pipeline that turns media into suggestions with honest, visible states.

## 2. Screens delivered
- **B2 — Capture image** (`Design Spec §4 B2`).

## 3. Design references
- `Capture Image (Dark) - Responsive` → `screens/99b7a1dce2924e21982207cc8812318f` (canonical)
- `Capture Image (Dark) - Mobile` → `screens/5aa6c04e3e624be8a72302ae97384a36`
- `Capture Image (Light) - Mobile` → `screens/3d56e805bb494e9886c04152ff569df0`
- ⚠️ No light-desktop variant exists — see `DESIGN-DISCREPANCIES.md` §CAPTURE-LIGHT; render from the dark canonical + light tokens, generate a variant only if ambiguous.
- Recognition state treatments (processing = pulsing sage glow; failed = terracotta border + Retry): reuse `Ui::RecognitionState` from D0.

## 4. Content & behaviour (from spec)
- Camera/upload interface; **clear indication of which box** the capture targets (capture-to-box clarity — Design Spec §6.2).
- Shutter/upload action; recent captures for this session; toggle/link to manual add.
- Phase-1 = **images only**; capture requires connectivity + successful upload; after upload recognition is queued server-side.
- Media state visible: uploaded → queued → processing → recognized → failed; failed offers retry (admin/contributor).
- Several captures in sequence without leaving the screen. **No offline queue** — show an honest "needs connection" failure (Design Spec §2, §5; Technical Foundation §12).

## 5. Domain & actions required
- `App::Media::Capture` (image-only, online upload via Active Storage, sets `captured_via: web`) → `App::RecognitionRuns::Enqueue` (Solid Queue).
- Recognition behind the provider adapter interface (`RecognitionProviders::Base` → `Result`/`DetectedObject`), with a **fake/stub provider** for deterministic local/test runs; `RECOGNITION_PROVIDER` env selects fake/openai/anthropic (Technical Foundation §10.1).
- `App::RecognitionRuns::Process` restores `Current` from job args, marks `processing`, persists normalized suggestions, applies the auto-confirm threshold (default 0.8) → `auto_confirmed` vs `pending_review`; run ends `succeeded | partially_succeeded | failed`.
- **No vendor schema / raw responses** in domain tables; adapter discards any bounding boxes (Technical Foundation §10.4, §6.3). `App::RecognitionRuns::Retry` creates a new run.
- Turbo/Stimulus for upload progress + recognition-state polling (Technical Foundation §12).

## 6. Acceptance criteria
- [ ] Layout matches the Capture screen; target box is always unambiguous.
- [ ] Image upload succeeds online; offline shows honest failure (no silent queue).
- [ ] Media moves through uploaded→queued→processing→recognized/failed, visible live.
- [ ] Suggestions created; ≥threshold → auto_confirmed, <threshold → pending_review.
- [ ] Failed run retryable by admin/contributor; manual add reachable even on failure.
- [ ] Fake provider yields deterministic suggestions in test/dev; no bounding boxes stored.
- [ ] Sealed-box capture remains blocked (from D3).
- [ ] Dark default; strings I18n.

## 7. Runtime verification
`/product-review` with `RECOGNITION_PROVIDER=fake`: capture into a box → watch state progress → land suggestions → verify auto-confirm vs pending split in DB/UI. Force a provider failure → verify failed state + retry (contributor) and that manual add still works. Verify the downstream effect (suggestions/items actually created), not just the screen — `AGENTS.md` "test full user journeys".

## 8. Out of scope
The review UX itself (D6), search indexing of confirmed items (D8), MCP `add_media_to_box` (D13).

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `ui-04`:
