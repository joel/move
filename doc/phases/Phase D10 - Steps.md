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
_filled after /product-review_

## 11. PR review
_filled after PR opens_

## Final summary
_filled at close_
