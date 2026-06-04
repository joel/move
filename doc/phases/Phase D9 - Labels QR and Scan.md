# Phase D9 — Labels, QR & Scan

**Release tag:** `ui-09`
**Branch:** `feature/ui-09-labels-qr-scan`
**Design status:** ✅ Design complete — E1 + E2 designed in Stitch (`DESIGN-DISCREPANCIES.md` §E2)
**Depends on:** D0, D1, D2, D3
**Domain backing:** `prompts/Phase 08` (labels, manifests, scan). Domain Spec §4.8 (qr_token), §12, §8; Design Spec §4 E1, E2.

---

## 1. Goal
Produce what goes on/in the box (opaque exterior label + authenticated manifest) and let an authenticated member open a box by scanning its QR — without ever leaking contents.

## 2. Screens delivered
- **E1 — Box label & QR** (`Design Spec §4 E1`). ✅ designed.
- **E2 — Scan QR** (`Design Spec §4 E2`). ✅ designed across 4 state screens.

## 3. Design references (open before coding)
- **E1:** `Box Label & QR Print Preview (Dark)` → `screens/ea5a8a69d7494226a3c93d7ad8f30635`; `… - Mobile` → `screens/65a64f8df02b49488130244f0f60cc94`.
- **E2 (all mobile, one per state):** `Scan QR - Scanning State` → `screens/09263080e5d549b2b7f4450afc0a4daf`; `Scan QR - Resolved State` → `screens/8086fa259d204e2eb6bb56b9ff5e9fe2`; `Scan QR - Unrecognized State` → `screens/de9f2c2af36242fea3336c33dca99b5e`; `Scan QR - Archived State` → `screens/47000d2e4b61472b9f954dc4c73ca89d`.

## 4. Content & behaviour (from spec)
**E1 Label & QR:** exterior label preview containing **only box number, room, and QR — no contents**; A7 print target. Separate option to generate an **authenticated detailed manifest** (A4 print), which **warns contents are sensitive** and is not publicly shareable. No public export/share in Phase 1.
**E2 Scan QR:** scanner view; authenticated-resolution state; unrecognized/foreign-QR state; read-only archived state. QR token resolves only through the app; user must be authenticated + have Move access; **scan opens box contents and does not change box status**; admin/contributor see edit/unpack actions, viewer read-only.

## 5. Domain & actions required
- `App::Labels::GenerateExterior` (A7, opaque), `App::Manifests::Generate` (A4, auth-gated, sensitive-content warning; optional audit of the sensitive read — Domain §12.3, Technical Foundation §19).
- `App::Qr::Resolve` (auth-gated; returns box listing; **never** changes status; cross-org/foreign token → non-disclosing failure; archived → read-only). QR token permanent + opaque (Domain §12.1).

## 6. ✅ Design status (resolved)
E2 is designed across four Stitch state screens (scanning, resolved, unrecognized, archived — see §3); recorded in `README.md` §2 and `DESIGN-DISCREPANCIES.md` §E2. During build, verify the Resolved State reveals only box identity (number + room, **no contents**) and shows edit/unpack actions for admin/contributor only (viewer read-only). E1 + E2 ship together under `ui-09`.

## 7. Acceptance criteria
- [ ] E1 label preview matches Stitch; contains **only** number/room/QR; A7 print view correct.
- [ ] Manifest is A4, authenticated, warns before showing contents, not publicly shareable.
- [ ] E2 matches the four Stitch state screens; all four states present.
- [ ] QR resolves only when authenticated + Move member; scan does **not** change status; foreign/cross-org token → non-disclosing failure; viewer read-only; archived read-only.
- [ ] Dark default; strings I18n.

## 8. Runtime verification
`/product-review`: generate a label (verify no contents) and a manifest (verify warning + auth gate). Scan a valid QR (opens contents, status unchanged), a foreign QR (non-disclosing), and as a viewer (read-only). Confirm the manifest is unreachable without auth.

## 9. Out of scope
Unpacking checklist actions (D10); MCP tools (D13).

## 10. Phase audit trail
_Fill on execution:_ Issue: · PR: · E2 Stitch screen id: · Verification: · Release `ui-09`:
