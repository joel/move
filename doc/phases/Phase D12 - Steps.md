# Phase D12 — Volume & Weight Summary · Steps (flight recorder)

Append-only log of what was done, in order, and why. See
`Phase D12 - Volume and Weight Summary.md` for the plan and `README.md` §2 for
the screen↔phase map.

## 1. Issue & plan
- **Issue:** [#100 — D12 Volume & weight summary (F2)](https://github.com/joel/move/issues/100) (`enhancement`).
- **Plan:** `doc/phases/Phase D12 - Volume and Weight Summary.md`.
- **Design opened (mandatory):** `Summary & Volume (Dark) - Responsive`
  `screens/9c53bc10b02f4dd7864af8f3248abb02` (+ mobile
  `screens/1bab812966eb41ca80cc7c2cbc7535b4`). Built light from Refined-Palette
  tokens (Stitch is dark-only).
- **Product decision (user-confirmed):** the Metric/Imperial toggle **persists
  Move#unit_system** (rather than an ephemeral per-page override). Canonical
  storage stays cm/kg, so the toggle changes display only (Technical Foundation
  §6.2); it is hidden on an archived (read-only) Move.

## 4. Branch
- `feature/summary` off `main`.

## 7. Commits
- **UnitConversions** — factor the metric↔imperial factors out of
  `BoxMeasurements` into a shared `UnitConversions` module so the new presenter
  reuses one source (no behaviour change).
- **Moves::VolumeSummary** — read action aggregating the Move's boxes into
  total + per-room volume/weight, box count, and a missing-dimension count.
  Volume/weight derived in code (never persisted); per-room `nil` distinguishes
  "nothing measured" from zero; roomless boxes fall into an unassigned bucket
  sorted last. Emits an auditable `move.summary_viewed` event; mutates nothing,
  so it reads an archived Move too.
- **MoveMeasurements** — presenter formatting the totals for the Move unit
  system, returning value + unit separately (`Quantity`) so the view sizes the
  number and unit independently. m³/ft³ with trailing zeros stripped; kg/lb as a
  delimited whole number.
- **F2 view + locale** — `Views::Summaries::Show` (header + unit toggle, honest
  incomplete-data banner linking to Boxes, three-metric bento, per-room
  breakdown reusing `Ui::ProgressBar`, empty state); `summaries.*` strings.
- **Route + controller + nav** — `GET /moves/:id/summary` and
  `PATCH .../summary/unit_system`; thin `SummariesController` (member read; toggle
  is editor-only and refuses an archived Move). Pointed the existing `:summary`
  nav destination at the route (was a stub).
- **Seeds** — gave Portland Archive's box dimensions so the archived Move's
  read-only summary shows a real total. The active Seattle Relocation Move
  already seeds the full/partial/missing dimension mix across four rooms + an
  unassigned box, so F2 is showcase-ready on `db:seed`.

## 8. Runtime verification
Reset dev seed; rebuilt Tailwind (`tailwindcss:build`) + cleared precompiled
`public/assets` so the new view's utilities compile, then restarted. Verified
live at `https://acme.workeverywhere.docker` (signed in as `demo@example.com`):
- Nav **Summary** link resolves; page renders dark (default) and light.
- Seattle Relocation: **Total Volume 0.55 m³**, **Est. Weight 77 kg**, **8 boxes
  / 4 rooms**; incomplete-data banner reports **3 boxes** (#2/#4/#6); rooms
  sorted by volume desc (Garage→Living Room→Bedroom→Kitchen) with per-room
  missing-dimension notes; **Unassigned** bucket last showing "—".
- **Imperial toggle** → 19.37 ft³ / 170 lb; `Move#unit_system` persisted to
  `imperial`; box1 stored values unchanged (40×30×25 cm, 8 kg) — display-only.
- **Portland Archive** (archived): summary read-only with **no unit toggle**
  (0.06 m³, 10 kg, 1 box).
- Mobile (393×852): no horizontal overflow; banner/cards stack; bottom nav shows
  the Summary tab. No Bullet N+1 alerts (action eager-loads `boxes.includes(:room)`).

## Tests
- `spec/actions/moves/volume_summary_spec.rb`, `spec/presenters/move_measurements_spec.rb`,
  `spec/requests/summaries_spec.rb` (all view branches: banner present/absent,
  empty state, non-member 404, editor/viewer/archived toggle paths).
- Full suite green: 513 examples / 0 failures (+26 pre-existing pending scaffolds);
  35 system; RuboCop + ErbLint + Brakeman clean.
