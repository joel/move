# Phase D2 — Boxes Home · Steps (flight recorder)

Append-only log of how the work unfolded. Companion to `Phase D2 - Boxes Home.md`.

## Decisions (confirmed with maintainer before coding)
- **Routing:** boxes nested under a Move — `/moves/:move_id/boxes`. A1 Move cards
  link to their Boxes Home. (A box always belongs to a Move; supports >1 move/org.)
- **Rooms:** minimal `Room` model (name unique per Move); `Box.room_id` nullable;
  `Boxes::Create` find-or-creates by name. Full vocabulary management is D7.
- **Item / pending-review counts:** placeholders in D2 (Items land in D5).
- **No `organization_id`** — matches D1 (Apartment schema-per-tenant).

## Build order (atomic commits)
1. `6f71ed9` — Room + Box models + migrations (rooms, boxes) + factories + model specs.
   - `Box.number` constrained numeric in D2 (safe `number::bigint` ordering +
     simple next-number generator); `qr_token` permanent; `missing_dimensions?`.
2. `69dd8b3` — `Boxes::Create` action (auto number, qr_token, room find-or-create,
   dims; emits `box.created`) + action spec.
3. `7becb50` — App-shell page layout: extracted `Views::Layouts::ChromeHead`
   (shared `<head>`/theme-boot), added `AppShellLayout` rendering
   `Components::Ui::AppLayout`. **First real adoption of the D0 sidebar shell.**
4. `02fb17a` — Boxes Home feature: `BoxesController` + `BoxPolicy`, nested route,
   `Views::Boxes::Index`/`New`, `BoxCard` (Ui::Card micro-bar + ProgressBar),
   `BoxForm`, A1 Move-card link, `boxes.en.yml`, request + system specs.

## Gotchas hit
- **`format` is a Phlex element helper** — `format("%02d", n)` raised
  `ArgumentError (given 2, expected 0)`. Use `Kernel.format(...)`.
- `Box#room_name` is a **virtual `attr_accessor`** so the new-box form binds a
  typed room name; `Boxes::Create` resolves it (case-insensitive find-or-create).
- Apartment `db:migrate` migrated existing tenants automatically (1/1) — the new
  tables clone into tenant schemas; `structure.sql` holds the public template.

## Verification
See the audit trail in the phase doc §9. Live-verified on `joel.move-easy.docker`,
desktop + mobile, screenshot-matched to the Refined-Palette Stitch screen.
