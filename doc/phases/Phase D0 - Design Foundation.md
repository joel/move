# Phase D0 — Design Foundation

**Release tag:** `v0.5.0-design-foundation`
**Branch:** `feature/design-foundation`
**Design status:** ✅ Design complete (no missing screens)
**Depends on:** nothing (first phase)
**Blocks:** every other phase (D1–D13)

> **This phase ships no customer feature.** It encodes the Stitch design system as Tailwind tokens + reusable Phlex primitives + theming, and proves them in an internal style guide. Getting this right is the precondition for every customer-facing screen.

---

## 1. Goal

Translate the Stitch **`Move Design`** design system into the Rails app so that every later phase composes screens from shared, on-brand primitives and never hand-codes colour, spacing, radius, or type values.

---

## 2. Design references (read first)

- **Token sheet (authoritative):** `projects/13869765800416404511` → `designTheme.designMd`. Pull it live with `mcp__stitch__get_project name=projects/13869765800416404511`. It defines colours, typography, spacing, radii, elevation, and component rules. Mirror is in §4 below.
- **Art direction:** `Move - Design Specification v0.2.md §2` (mobile-first, modern, lightweight, **dark-mode-first**) and the original `direction_a_light_and_dark_mobile.html` → `screens/7062889364062299479`.
- **Component cues in situ:** open any `… - Refined Palette` screen (e.g. `Boxes Home (Dark) - Refined Palette` `screens/bda13a39e9cb48b99d72ea5af19041d7`) to see buttons, cards, chips, nav, and recognition states applied.
- **Palette + nav decisions:** `DESIGN-DISCREPANCIES.md` §PALETTE, §NAV, §AUTH (all ✅ decided).

---

## 3. Brand intent (must be preserved by every later phase)

"**Mindful Moving** / Organic Minimalism" — calm, supportive, unhurried. Heavy whitespace, restricted nature palette, soft rounded shapes, low information density (one primary task per screen). **Pure black (`#000000`) is prohibited;** depth comes from tonal layering, not shadows; all buttons are pill-shaped; major containers use a 20px radius.

---

## 4. Tokens to encode

Encode these as Tailwind theme extensions (`config/tailwind.config.js`) **and** CSS custom properties for light/dark in `app/assets/stylesheets/application.css`. Names below are the canonical token names.

### 4.1 Colour — canonical "Refined Palette" surfaces + accent
| Token | Dark | Light |
|-------|------|-------|
| `page` | `#2A2822` | `#F2ECE1` |
| `card` | `#34312A` | `#FAF6EF` |
| `accent-sage` | `#9FB089` | (sage) |
| `text-warm` | `#ECE7DC` | `#33302b` |

### 4.2 Colour — Material-3 semantic system (state colours, imported wholesale)
Dark-mode values from `designTheme.namedColors`:
`primary #b9cda9` / `on-primary #25351c` / `primary-container #849676`; `secondary #ffb59b` (terracotta — **Fragile** + soft warnings) / `on-secondary #53220e`; `tertiary #e5bbcf`; `error #ffb4ab` / `on-error #690005` / `error-container #93000a`; `surface #15130f` … `surface-container-highest #37342f`; `on-surface #e8e1da`; `on-surface-variant #c5c8bd`; `outline #8f9288`; `outline-variant #444840`.
Light-mode equivalents: derive from the same Material-3 ramp (Stitch provides the dark ramp; generate the light ramp from the same seed `#7e9070` if a light value is missing).

> **Usage law:** sage = primary actions / success / progress. terracotta = highlights / Fragile / soft warnings. charcoal-brown = text + structural background.

### 4.3 Typography — **Plus Jakarta Sans** (self-host via Propshaft; no Google CDN)
| Token | Size / weight / line-height |
|-------|------------------------------|
| `headline-xl` | 40 / 700 / 48, ls −0.02em (Move titles, welcome) |
| `headline-lg` | 32 / 700 / 40, ls −0.01em (`-mobile` = 28/700/36) |
| `headline-md` | 24 / 600 / 32 |
| `body-lg` | 18 / 400 / 28 |
| `body-md` | 16 / 400 / 24 |
| `label-caps` | 12 / 700 / 16, ls 0.1em (Rooms/Tags/Categories labels) |

### 4.4 Radii — `sm .25rem`, `DEFAULT .5rem`, `md .75rem`, `lg 1rem`, `xl 1.5rem`, `full 9999px`. **Cards/inputs = 20px (`xl`-ish); buttons/chips/progress = `full`.**

### 4.5 Spacing — 4px baseline. `margin-mobile 20px`, `margin-desktop 48px`, `gutter 16px`, `stack-gap 12px`, `section-gap 32px`.

### 4.6 Elevation — **tonal layering, not shadows.** Card = one step lighter than page (`#34312A` over `#2A2822`) + 1px border at ~5% white. Pressed = scale 0.98 + reduced tonal contrast ("sink"). Processing = soft pulsing sage glow.

---

## 5. Deliverables

### 5.1 Theming infrastructure
- `dark` as the **default** theme (`<html class="dark">`); class strategy in Tailwind.
- A Stimulus `theme` controller: toggle, persist to `localStorage`, respect `prefers-color-scheme` on first load. Wire to the existing dark-mode toggle path so `/product-review`'s dark-mode check passes.
- CSS variables for `page`/`card`/`text-warm`/`accent-sage` swapped per theme; Material-3 tokens mapped to Tailwind colours.

### 5.2 Core Phlex primitives (`app/components/ui/`)
Build, with light/dark + states, matching the design-system "Components" section:
- `Ui::Button` — variants `primary` (sage, dark text, pill), `secondary` (terracotta or sage-outline, pill), `ghost`; pressed = sink; full-width + icon options.
- `Ui::Card` — 20px radius, tonal lift, 1px hairline border; optional bottom "summary micro-bar" slot (used by Boxes Home).
- `Ui::Chip` — pill, `label-caps`, low-saturation sage/terracotta tints; `kind: :room | :tag | :category` to distinguish.
- `Ui::Field` / `Ui::Select` — large heavily-rounded (20px) containers on `card` colour; label + error slot (I18n).
- `Ui::QuantityAdjuster` — horizontal pill with large `+` / `−` tap targets.
- `Ui::ProgressBar` — pill-shaped, sage fill (boxes packed / items reviewed).
- `Ui::RecognitionState` — badge/treatment for `queued | processing | succeeded | failed | needs_correction | auto_confirmed | pending_review`; processing = pulsing sage glow, failed = terracotta border + Retry overlay. (Single source of truth reused by D2/D3/D4/D6.)
- `Ui::EmptyState`, `Ui::SectionHeader`, `Ui::Toast` (fold in existing `flash_toasts.rb`).
- Duotone / rounded-line icon set under `app/components/icons` (extend existing).

### 5.3 Navigation chrome (stateless in D0; wired to Move context in D1)
- `Ui::BottomTabBar` (mobile) — docked/floating, 4–5 icons: **Boxes, Search, Scan, Summary, Menu** (`Design Spec §3`). Active = sage vertical pill / fill.
- `Ui::Sidebar` (desktop ≥`lg`) — 280px, blends into `page`, active = sage vertical pill.
- `Ui::AppLayout` — responsive container applying `margin-mobile` / `margin-desktop`, single-column mobile stack, desktop sidebar + content.
- ℹ️ The **Scan** and **Menu** slots target screens whose *routes* land later (E2 in D9, F3 in D13) — the designs exist now. Render the slots; point them at stub routes until those phases ship.

### 5.4 Internal style guide
- A dev-only route (e.g. `/style-guide`, gated to non-production or admin) rendering every primitive in every state, light + dark, mobile + desktop. This is the verification surface for this phase and a living reference for all later phases.

### 5.5 I18n scaffolding
- `config/locales/en.yml` namespaces for shared UI strings (`ui.buttons.*`, `ui.states.*`, `ui.nav.*`). Establish the convention; no hard-coded copy in components.

---

## 6. Acceptance criteria

- [ ] Tailwind config + CSS expose every token in §4 by canonical name; no magic hex/px in components.
- [ ] Plus Jakarta Sans self-hosted and applied via the typography tokens.
- [ ] Dark is default; toggle persists and matches the Stitch dark screens; light matches the Refined-Palette light tokens.
- [ ] Every primitive in §5.2 exists with light/dark + interactive (hover/pressed/disabled) states and renders in the style guide.
- [ ] `Ui::RecognitionState` covers all seven states with the prescribed treatments.
- [ ] Bottom tab bar + sidebar render the five destinations with correct active treatment; Scan/Menu point at stubs.
- [ ] Existing Rodauth + welcome views re-skinned with the new tokens (no behaviour change) — `DESIGN-DISCREPANCIES.md` §AUTH.
- [ ] No customer-facing string hard-coded; all via I18n.
- [ ] Style guide visually matches the Stitch components when compared screenshot-to-screenshot.

## 7. Runtime verification
- `bin/cli app rebuild && bin/cli app restart` (Tailwind rebuild required for new classes — Technical Foundation §12).
- `/product-review`: home (logged out/in), dark-mode toggle, flash/toast, and the `/style-guide` route. Compare primitives against `screens/bda13a39e9cb48b99d72ea5af19041d7` and the design-system sheet.

## 8. Out of scope
Any Move domain model, any real screen data, any feature behaviour. Those start in D1.

## 9. Phase audit trail
_Fill on execution:_ Issue: · PR: · Verification: · Release `v0.5.0-design-foundation`:
