# Phase D3 — Box Detail & Lifecycle

**Release tag:** `v0.8.0-box-lifecycle`
**Branch:** `feature/box-lifecycle`
**Design status:** ✅ Design complete
**Depends on:** D0, D1, D2
**Domain backing:** `prompts/Phase 03` (box lifecycle, measurements, QR token basics) + `prompts/Phase 04` (media gallery surface). Domain Spec §4.8, §5.2; Design Spec §4 B1.

---

## 1. Goal
Deliver the single-box hub: identity, room, dimensions/volume/weight, item inventory with pending-review count, full-media gallery, recognition runs, and the full lifecycle action set.

## 2. Screens delivered
- **B1 — Box detail** (`Design Spec §4 B1`).

## 3. Design references
- `Box Detail (Dark) - Refined Palette` → `screens/bf7c4f4817464dd09f2b6d0b859cdf1d` (canonical)
- `Box Detail (Dark) - Mobile` → `screens/29f0268b59e64a4d89e91f556b6cbfb5`
- Also `Box Detail (Light)` `screens/027f399dbf99409a978346cd86fcd4df`, `Box Detail (Dark) - Responsive` `screens/228a8b832f6047c9b0123e7cf9223bb4`, `Box Detail (Light) - Mobile` `screens/4fe3b1729e1d4adf82a6fb0b3cdf11b2`.

## 4. Content & behaviour (from spec)
- Box number + status; room; dimensions L/W/H + **derived** volume + optional weight (canonical storage, display in Move unit system — Technical Foundation §6.2).
- Item inventory with pending-review count; **full-source-media gallery (thumbnails of full media, never crops)**.
- Recognition runs + failed/retry state when relevant.
- Actions: capture image, add item manually, review, generate label/QR, **seal, unseal, mark in transit, mark unpacking, mark unpacked**.
- States/rules: number auto-generated + unique per Move, override allowed on create; **sealing requires a room**; sealed box can be unsealed; **capture into a sealed box is blocked until unsealed**; recognition from pre-seal media may still complete; archived Move → read-only listing, no mutating actions.

## 5. Domain & actions required
- `App::Boxes::Update` (number, room, dimensions, weight, tags); `App::Boxes::TransitionStatus` validating the `packing → sealed → in_transit → unpacking → unpacked` lifecycle (Domain §5.2), incl. seal-requires-room and sealed-capture-block guards.
- Derived volume computed, never stored as source-of-truth; `measured`-style canonical dims (Technical Foundation §6.2).
- Media gallery reads media for the box (full files; generic thumbnails allowed, **no crop variants** — Technical Foundation §13).
- Reuse `Ui::RecognitionState` for run/retry display; retry gated to `move_writable?`.

## 6. Acceptance criteria
- [ ] Matches the Refined-Palette Box Detail screen (dims block, gallery, action set).
- [ ] Volume derived from dims and shown in Move units; weight optional.
- [ ] Lifecycle actions enforce: seal-requires-room, unseal works, sealed-capture blocked, status transitions valid server-side even with stale UI.
- [ ] Media gallery shows full media only — **no crops/bounding boxes anywhere**.
- [ ] Recognition runs + failed/retry visible; retry only for admin/contributor.
- [ ] Archived Move → read-only.
- [ ] Dark default; strings I18n.

## 7. Runtime verification
`/product-review`: open a box → change room → set dimensions (verify volume) → seal (blocked without room, then succeeds) → attempt capture on sealed box (blocked) → unseal. Verify viewer sees read-only; verify a failed recognition run shows retry for contributor only.

## 8. Out of scope
The capture camera flow (D4), review queue interior (D6), label/QR generation (D9), unpacking checklist (D10), summary (D12).

## 9. Phase audit trail
- **Issue:** #44
- **PR:** #45 (`feature/box-lifecycle`)
- **Verification:** `/product-review` on `acme.workeverywhere.docker` — box detail
  (identity, room/status chips, dimensions + derived volume `0.030 m³` + weight),
  live **Unseal** transition, live **seal-requires-room** guard (roomless box
  stays packing with the flash), capture hidden once sealed, archived read-only
  (system spec). Screenshot-matched to `Box Detail (Dark) - Refined Palette`.
  Full suite + RuboCop green; no Bullet N+1.
- **Deferred (annotated against §6):**
  - **Items inventory** (list/pending-review/delete) → **D5** (Item model). Empty
    placeholder for now.
  - **Media gallery** (full-media thumbnails, never crops) + **Capture image** →
    **D4** (Media + capture). Empty gallery; capture/add-item entries inert.
  - **Recognition runs / failed-retry** → **D4**; `Ui::RecognitionState` is the
    wired integration point.
  - **Generate label/QR** → D9.
- **Release `v0.8.0-box-lifecycle`:** _pending merge._
