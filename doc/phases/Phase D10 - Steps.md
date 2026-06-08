# Phase D10 — Unpacking Mode · Steps (flight recorder)

Append-only log of what was done, in order, and why. See
`Phase D10 - Unpacking Mode.md` for the plan and `README.md` §2 for the
screen↔phase map.

## 1. Issue & plan
- **Issue:** [#89 — Phase D10 — Unpacking Mode (E3)](https://github.com/joel/move/issues/89) (`enhancement`).
- **Plan:** `doc/phases/Phase D10 - Unpacking Mode.md`.
- **Design opened (mandatory):** `Unpacking Mode - Active Checklist`
  `screens/8e990c6d258d473cad16101819689246` + `Unpacking Mode - Box Unpacked
  Celebration` `screens/2cb7c29c027247f8955004bda7b8740b`.
- **Product decision:** celebration *Undo* = **reopen box only** (unpacked →
  unpacking, items stay `removed` and are restored individually) — the cascade
  only fires on the forward `→ unpacked`. User-confirmed.

## 4. Branch
- `feature/unpacking` off `main`.

## 7. Commits
- **Domain** — `Boxes::TransitionStatus` cascades in-box items → removed on
  `→ unpacked` (one transaction); `unpacked → unpacking` reverse edge added to
  `Box::TRANSITIONS`; `Box#unpacking?/#unpacked?` + `Item.removed` scope. Specs.
- **Surface** — `UnpackingController` (show / remove / restore / complete /
  reopen) + routes; `Views::Unpacking::Checklist` + `…::Celebration`; box-detail
  "Open unpacking" entry; `unpacking.*` locale.
- **Specs** — request (render, toggles, cascade, reopen, archived) + system
  (enter→check off, complete→Undo, archived read-only).
- **Seeds** — box #7 (`unpacking`) given 3 in_box + 2 removed items.

Design adaptations vs the Stitch E3 screens (deliberate, recorded here):
- The sticky bottom action bar is rendered **in-flow** instead, so it coexists
  with the app shell's mobile bottom tab bar; the **progress card** is made
  sticky to keep the remaining-count visible while scrolling (§6 intent).
- The celebration **Undo** reopens the box only (unpacked → unpacking); removed
  items are restored individually on the checklist (user-confirmed).

## 8. Runtime verification
`/product-review` against the dev app (reset + reseeded; box #7 = 3 in_box +
2 removed). All green:
- Box detail → "Open unpacking" entry → checklist (sticky "3 of 5 remaining",
  left-aligned tap-targets, dimmed Unpacked section).
- Remove an item → settles into Unpacked, count drops to 2/5; restore → back to
  3/5. Mark box unpacked → cascade verified in DB (in_box 0, removed 5) →
  celebration matches the Stitch screen. Undo → box reopened to `unpacking`,
  items stay removed (all-clear empty state renders).
- Archived Move → READ ONLY chip, static rows, no toggle/CTA.
- Mobile 393×852: no horizontal overflow, full-width tap-targets, bottom tab bar
  clear of the in-flow CTA. Light + dark tokens both adapt. No Bullet N+1 alerts.

**Asset note (not a code bug):** new Tailwind utilities (`text-left`, the
celebration's `blur-2xl`/`border-4`, etc.) were absent in dev until
`bin/rails tailwindcss:build` + `assets:precompile` + app restart (`app rebuild`
alone doesn't recompile CSS — see agent memory `product-review-asset-staleness`).
Prod precompiles at image build, so unaffected.

## 11. PR review
- **PR:** [#90](https://github.com/joel/move/pull/90).
- **Round 1 (Codex):**

| Finding | Severity | Resolution |
|---------|----------|------------|
| `remove`/`restore` toggles weren't guarded to `unpacking` boxes — an item could be marked removed/restored outside the E3 lifecycle (e.g. restore on an `unpacked` box leaves the celebration over an in_box item) | P2 | Fixed — added `require_active_checklist` (status == `unpacking`) to both toggles + request specs. `complete`/`reopen` already constrained by `TransitionStatus` validation. Thread resolved; Codex re-review came back clean ("no major issues"). |

## Final summary
_filled at close_
