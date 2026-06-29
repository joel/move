# Move — Visual Design System

> **"Mindful Moving / Organic Minimalism."** Calm, supportive, unhurried. Heavy
> whitespace, a restricted nature palette, soft rounded shapes, low information
> density (one primary task per screen).

This is the consolidated, human-readable reference for Move's visual language —
colour, type, spacing, radius, elevation, motion, and the Phlex component library.
Build every customer-facing surface from these tokens and components; **never
hand-code a colour, spacing, radius, or type value.**

## Source of truth (in order)

1. **Google Stitch — `Move Design`** (`projects/13869765800416404511` →
   `designTheme.designMd`). The originating design system; pull live via the Stitch
   MCP (`mcp__stitch__get_project`). See `CLAUDE.md` → *Design source of truth*.
2. **`app/assets/tailwind/application.css`** — the in-code authority. Tailwind v4 is
   CSS-first: the `@theme` block both generates utilities **and** emits CSS custom
   properties; runtime `--c-*` variables swap between light (`:root`) and dark
   (`.dark`). `config/tailwind.config.js` mirrors these for documentation only.
3. **`doc/phases/Phase D0 - Design Foundation.md`** — the foundation brief (rationale,
   acceptance criteria, deliverables).
4. **This file** — a flat consolidation of 1–3 for quick reference. If it ever
   disagrees with `application.css`, the CSS wins; fix this doc.

> The internal **`/style-guide`** route (dev/admin only) renders every primitive in
> every state, light + dark — the living visual reference and verification surface.

---

## 1. Brand law (never violate)

- **sage** → primary actions / success / progress.
- **terracotta** → highlights / **Fragile** / soft warnings.
- **charcoal-brown** → text + structural background.
- **Pure black (`#000000`) is prohibited.** Depth comes from **tonal layering, not
  shadows** — a card is one tonal step lighter than the page plus a 1px hairline edge.
- **Buttons / chips / progress = pill** (`rounded-full`); **cards / inputs = 20px**
  (`rounded-card`).
- **Dark is the default theme.** Light is a first-class equal, not an afterthought.
- Mobile-first, low density: one primary task per screen, generous whitespace.

---

## 2. Colour

Canonical names map to theme-swapped runtime variables, so the same utility
(`bg-page`, `text-text-warm`, …) resolves correctly in both themes. Two layers:
the **Refined Palette** (canonical surfaces + accent) and the **Material-3 ramp**
(semantic state colours).

### 2.1 Refined Palette — surfaces & accent

| Token (utility stem) | Dark | Light | Use |
|---|---|---|---|
| `page` | `#2A2822` | `#F2ECE1` | App background |
| `card` | `#34312A` | `#FAF6EF` | Card / input surface (one step lighter than page) |
| `card-border` | `#45413A` | `#E6DDCC` | Card / input hairline edge |
| `accent-sage` | `#9FB089` | `#4C6443` | Primary accent (light deepens for AA text) |
| `text-warm` | `#ECE7DC` | `#33302B` | Primary text |
| `muted` | `#ABA496` | `#6B6658` | Secondary / placeholder text |

### 2.2 Material-3 ramp — semantic state colours

Pairs are `<role>` + `on-<role>` (foreground) + `<role>-container`. Dark values are
imported wholesale from `designTheme.namedColors`; light is derived from seed
`#7E9070`.

| Role | Dark `role` / `on` / `container` | Light `role` / `on` / `container` | Meaning |
|---|---|---|---|
| `primary` | `#B9CDA9` / `#25351C` / `#849676` | `#4C6443` / `#FFFFFF` / `#CEE9BB` | Primary actions / success / progress (sage) |
| `secondary` | `#FFB59B` / `#53220E` / `#6F3722` | `#8F4C34` / `#FFFFFF` / `#FFDBCF` | Highlights / **Fragile** / soft warnings (terracotta) |
| `tertiary` | `#E5BBCF` / `#442837` / `#AC8698` | `#735767` / `#FFFFFF` / `#FFD8EA` | Pending-review accent |
| `error` | `#FFB4AB` / `#690005` / `#93000A` | `#BA1A1A` / `#FFFFFF` / `#FFDAD6` | Destructive / failure |

**Surfaces:** `surface` `#15130F`/`#FAF6EF`, then `surface-container`
`#221F1B`/`#EFE8DC`, `…-high` `#2C2A25`/`#E9E2D4`, `…-highest` `#37342F`/`#E3DCCD`;
foregrounds `on-surface` `#E8E1DA`/`#1C1B16`, `on-surface-variant`
`#C5C8BD`/`#4A473E`. **Outlines:** `outline` `#8F9288`/`#7C7A6F`, `outline-variant`
`#444840`/`#CDC8BA`.

> A new view uses the canonical tokens above. The legacy `--ha-*` aliases in
> `application.css` exist only to re-skin the pre-D0 shell — do not reach for them in
> new work.

---

## 3. Typography

**Plus Jakarta Sans**, self-hosted via Propshaft (no Google CDN), weight axis
`200–800`. Use the named type tokens — never raw `text-[..]`.

| Token (utility) | Size / line-height / weight / tracking | Use |
|---|---|---|
| `text-headline-xl` | 40 / 48 / 700 / −0.02em | Move titles, welcome |
| `text-headline-lg` | 32 / 40 / 700 / −0.01em | Section titles (desktop) |
| `text-headline-lg-mobile` | 28 / 36 / 700 | Section titles (mobile) |
| `text-headline-md` | 24 / 32 / 600 | Card / result titles |
| `text-body-lg` | 18 / 28 / 400 | Lead body |
| `text-body-md` | 16 / 24 / 400 | Body |
| `text-label-caps` | 12 / 16 / 700 / 0.1em, UPPERCASE | Room labels, chips, overlines |

Typical responsive headline: `text-headline-lg-mobile md:text-headline-xl`.

---

## 4. Radius

| Token | Value | Use |
|---|---|---|
| `rounded-sm` | 4px | rare, tight insets |
| `rounded-md` | 12px | nested elements |
| `rounded-lg` | 16px | larger nested blocks |
| `rounded-xl` | 24px | large containers |
| **`rounded-card`** | **20px** | **cards & inputs (default container radius)** |
| `rounded-full` | 9999px | **buttons, chips, progress, avatars** |

---

## 5. Spacing

4px baseline. Named rhythm tokens compose with every spacing utility
(`p-*`, `gap-*`, `m-*`):

| Token | Value | Use |
|---|---|---|
| `gutter` | 16px | grid / inline gutters |
| `stack-gap` | 12px | vertical rhythm between stacked items (`gap-stack-gap`) |
| `section-gap` | 32px | between major sections |
| `margin-mobile` | 20px | page side margin (mobile) |
| `margin-desktop` | 48px | page side margin (desktop) |

---

## 6. Elevation & motion

- **Tonal layering, not shadows.** Lift = card colour over page colour + a 1px
  hairline (`border-hairline` / `--c-hairline`: 5% white in dark, 6% black in light).
  Card hover nudges `translateY(-2px)` and lightens to `surface-container-high`.
- **Press = sink** — `scale(0.98)` on buttons, `0.95` on chips.
- **Processing = soft pulsing sage glow** (`.ui-pulse-glow`).
- **Just-created highlight** — a one-shot sage ring that fades (`.box-added-highlight`,
  used for "make the result visible" — see `doc/project/ux-conventions.md`).
- Standard easing `cubic-bezier(0.4, 0, 0.2, 1)`, ~200–300ms. Entrances:
  `.ha-fade-in` / `.ha-rise`. **All motion is disabled under
  `prefers-reduced-motion`.**

---

## 7. Component library (`app/components/`)

Compose screens from these Phlex primitives — don't re-implement their look. Each
covers light/dark and its interactive states.

### `Ui::Button` — pill; `<a>` when `href:`, else `<button>`; press = sink
Variants: `primary` (sage fill, page-coloured text) · `secondary` (sage outline) ·
`terracotta` (highlights / Fragile) · `ghost` (chromeless, surface hover) · `danger`.
Options: `full_width`, `icon`, `disabled`.

### `Ui::Card`
20px radius, tonal lift, 1px hairline, no drop shadow; optional bottom "summary
micro-bar" slot.

### `Ui::Chip` — pill, `label-caps`, low-saturation tint
`kind: :room` (sage) · `:tag` (terracotta / `secondary`) · `:category` (neutral
`surface-container-high`). `selected: true` fills solid.

### `Ui::Field` / `Ui::Select`
Large 20px-radius container on `card`, sage focus ring, label + I18n error slot.

### `Ui::RecognitionState` — single source of truth for the AI pipeline badge
Seven states, each an icon + tint: `queued` (clock, neutral) · `processing`
(sparkles, pulsing sage glow) · `succeeded` (check, sage) · `failed` (alert,
terracotta/error border + Retry overlay) · `needs_correction` (pencil, terracotta) ·
`auto_confirmed` (bolt, sage outline) · `pending_review` (eye, tertiary).

### Other primitives
`Ui::ProgressBar` (pill, sage fill) ·
`Ui::EmptyState` · `Ui::SectionHeader` / `Ui::PageHeader` · `Ui::Toast` /
`FlashToasts` · `Ui::SaveStatus` · `Ui::ThemeToggle`.

### Overlays — native `<dialog>` + Stimulus
Three card/full-bleed overlay chromes built on native `<dialog>` (`showModal()` gives
focus-trap, Escape and a dimmed `::backdrop`). The first two share the `modal`
controller (`open` / `close` / `backdropClose`); the third has its own:
- **`.ha-modal`** — centred modal (capped 400px), e.g. the describe-before-sealing
  flow (`Components::BoxSealTrigger`).
- **`.ha-sheet`** — bottom sheet: full-width (capped 480px, centred on wide
  viewports), rounded top, slides up (`ha-sheet-up`, disabled under
  `prefers-reduced-motion`). Used by **`Components::Boxes::ManageSheet`** — the box
  detail's ⋮ "Manage box" overflow that holds the box's dimensions/weight (read-only)
  plus the secondary actions (lifecycle step(s), print label/manifest, edit, delete)
  so the screen shows one contextual hero. Rows are full-width `surface-container-high`
  pills (`text-error` for the destructive Delete row).
- **`.ha-lightbox`** — full-viewport, transparent/borderless photo viewer over a heavy
  (85%) blurred `::backdrop`; the contained `:detail` `<img>` floats centred
  (`object-contain`). Driven by the **`lightbox`** Stimulus controller
  (`open` / `close` / `prev` / `next` / `key` / `backdropClose`): grid tiles carry the
  photo's `:detail` src + caption + box href as `data-*`, and prev/next cycle (wrapping)
  over the rendered set with arrow-key support. Used by **`Components::Gallery::Grid`**
  (the Move-wide Gallery).

### Navigation chrome
`Ui::BottomTabBar` (mobile, docked) and `Ui::Sidebar` (desktop ≥`lg`, 280px) render
the five destinations **Boxes · Search · Scan · Summary · Menu**; active =
sage vertical pill. `Ui::AppLayout` is the responsive shell (mobile single-column +
tab bar; desktop sidebar + content) applying `margin-mobile` / `margin-desktop`.

### Icons (`app/components/icons/`)
Rounded-line / duotone set (1.6 stroke, `currentColor`), e.g. `Search`, `Clock`,
`Sparkles`, `Check`, `Boxes`, `Camera`, `ChevronRight`, `EllipsisVertical` (⋮
overflow), `Lock` (seal), `Printer` (print), `Trash` (delete). Size via `css:`
(e.g. `h-5 w-5`); colour by inheriting `text-*`.

---

## 8. Theming

- Dark is default: `<html class="dark">`. A Stimulus `theme` controller toggles the
  class, persists to `localStorage`, and respects `prefers-color-scheme` on first
  load (`Ui::ThemeToggle`).
- Only the `--c-*` runtime variables differ between themes; every canonical
  `--color-*` token points at them, so components are written once and theme
  correctly. Author both themes; verify the toggle in `/product-review`.

---

## 9. Rules for new UI

1. **No magic values.** Use a token utility (`bg-card`, `text-headline-md`,
   `rounded-card`, `gap-stack-gap`) — never a raw hex/px or arbitrary `*-[..]`.
2. **Compose primitives** from §7 before writing bespoke markup; extend the
   primitive if a genuinely new variant is needed.
3. **Cover every state deliberately** — empty / sparse / loading / processing /
   error, plus light + dark and mobile + desktop. Reproduce them in `/style-guide`.
4. **Behaviour follows `doc/project/ux-conventions.md`** (ordering, visible result,
   focus/scroll preservation) — this doc governs how it *looks*, that one how it
   *behaves*.
5. **No hard-coded copy** — all customer-facing strings via I18n (`config/locales/`).
6. New Tailwind utilities/components are stale in dev until rebuilt — see
   `AGENTS.md` (`tailwindcss:build` + `assets:precompile` gotchas).

---

## 10. See also

- `CLAUDE.md` → *Design source of truth (Google Stitch)* and *UX / interaction conventions*
- `doc/phases/Phase D0 - Design Foundation.md` — the foundation brief
- `doc/phases/DESIGN-DISCREPANCIES.md` — §PALETTE / §NAV / §AUTH decisions
- `doc/project/ux-conventions.md` — the behavioural counterpart to this visual system
- `app/assets/tailwind/application.css` — the authoritative `@theme` + runtime palette
