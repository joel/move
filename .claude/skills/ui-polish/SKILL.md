---
name: ui-polish
description: Review and elevate the visual design quality of Phlex components and pages in this project. Use this skill after building or modifying any UI component, page, or layout — or when the user says "polish this", "make it look better", "review the design", "improve the styling", "UI review", or "design review". Also trigger automatically after the ui-designer skill completes, or when the user asks about spatial composition, typography, color harmony, or visual refinement. This skill goes beyond functional correctness (that's ux-review) to focus on aesthetic impact, detail-level craft, and whether the interface feels intentionally designed rather than merely assembled.
---

# UI Polish Review

Audit and elevate the visual quality of Phlex components and pages. This skill focuses on aesthetic impact — not functional correctness (that's `ux-review`) or accessibility compliance. The question here is: **does this interface feel crafted, or just assembled?**

The primary source of truth is live screenshots from `agent-browser`, not code inspection. Read code to understand *how* something is built, but judge *what it looks like* from the browser.

## Project Design System

Before reviewing, internalize the project's visual language. The authoritative source for tokens, classes, fonts, radii, and timings is `app/assets/tailwind/application.css` — read it; the notes below describe the house style and intent.

- **CSS tokens**: `app/assets/tailwind/application.css` defines `--ha-*` variables (backgrounds, surfaces, accents, borders, text, shadows)
- **Component classes**: `ha-card`, `ha-button`, `ha-button-primary`, `ha-button-secondary`, `ha-button-danger`, `ha-input`, `ha-nav-item`
- **Accent palette**: the accent token `--ha-accent`, a secondary accent `--ha-accent-2`, and `--ha-danger` for destructive states (see the CSS for the actual colors)
- **Border radius language**: the project's convention is a larger radius on cards, a medium radius on inputs, full-pill radius on buttons, and smaller radii on nav items and small containers — verify the exact values in the CSS
- **Animations**: `ha-fade-in` and `ha-rise` entrances, staggered sidebar delays (timings defined in the CSS)
- **Dark mode**: Class-based (`.dark`), all tokens have dual values

## Tailwind JIT Constraint (Critical)

The Docker container compiles Tailwind CSS in JIT mode — **only classes already used in the codebase are included in the compiled stylesheet**. If you recommend a Tailwind class that has never been used before (e.g., `p-5`, `leading-relaxed`, `gap-5`), it will appear in the HTML class attribute but **have zero effect** until the Docker image is rebuilt with `bin/cli app rebuild`.

**Before recommending a Tailwind utility**, verify it exists in the current build by checking whether any existing component already uses it. Prefer classes already in use:
- Padding: `p-4` (16px), `p-6` (24px) — NOT `p-5`
- Gaps: `gap-2`, `gap-3`, `gap-4` — NOT `gap-5`
- Margins: `mt-1`, `mt-2`, `mt-3`, `mt-4` — all exist
- Spacing: `space-y-3`, `space-y-4`, `space-y-6`, `space-y-8` — all exist
- Text: `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl` — all exist

If a truly new class is needed, explicitly note in the recommendation: **"Requires `bin/cli app rebuild` to compile."**

## CSS Architecture Philosophy

This project uses a deliberate hybrid approach — Tailwind utilities for one-off styling, custom CSS classes for repeated visual patterns. Both have a role:

### When to extract a CSS component class

A visual pattern deserves its own class in `application.css` when it:
- Appears 3+ times across different Phlex components
- Carries more than 4-5 Tailwind utilities that always travel together
- Represents a semantic UI concept (a "card", a "badge", a "nav item") rather than a one-off arrangement
- Needs pseudo-element styling, complex transitions, or keyframe animations that Tailwind can't express inline

Example of a good extraction — the existing `ha-card` class bundles border-radius, border, background, and a signature drop shadow into a single token. Every card in the app gets the same visual DNA without repeating 5 utility classes.

### When to keep Tailwind inline

Use raw Tailwind utilities when:
- The styling is contextual and unlikely to repeat (a specific grid layout for one page)
- You're adjusting spacing, sizing, or alignment within a component
- You're applying responsive breakpoints (`sm:`, `md:`) to adapt layout
- The combination is short (3 or fewer utilities)

### The balance

The goal is **semantic CSS for visual identity, Tailwind for layout plumbing**. If you find yourself writing a long string of bracketed arbitrary values reproducing the card surface (radius + border + background + shadow) inline in a Phlex component — that's `ha-card` trying to escape. Extract it. But `class: "mt-4 flex items-center gap-3"` is fine inline.

When recommending new CSS classes, define them in `@layer components` inside `app/assets/tailwind/application.css`, following the existing `ha-*` naming convention.

## Review Dimensions

Evaluate each changed surface across these dimensions. Not every dimension applies to every component — focus on what matters for the specific UI.

### 1. Spatial Composition

The arrangement of elements within and between components. Look for opportunities to break out of rigid grid conformity.

**What to look for:**
- Are elements placed with clear intentionality, or do they just stack vertically by default?
- Is there meaningful hierarchy — does your eye land on the right thing first?
- Could asymmetric placement create more visual interest? (e.g., a title flush-left with metadata offset-right, rather than both centered)
- Would overlapping elements add depth? (e.g., a badge that breaks out of its card boundary, an avatar that sits on the edge of a section divider)
- Is negative space used deliberately — either generous breathing room OR controlled density — rather than accidentally?
- Do grid breaks or diagonal flows make sense here? (e.g., a staggered card layout instead of a strict 2x2 grid)

**Internal spacing audit (critical — check every component):**
- Does each card/component have consistent internal padding? The project convention is `p-6` for list-level cards, `p-4` for compact inline widgets.
- Are section headings separated from their content? A heading directly touching the first card below it is a spacing bug. Use `mb-4` or `mb-6` between section heading rows and their content grids.
- Are card action buttons (`ha-card-actions`) visually separated from content above? The CSS class provides a top margin and a `border-top` — verify it's actually being used and not replaced with inline layout.
- Inside cards, is there vertical breathing room between: overline → title → metadata → description → actions? Use `mt-1` for tight relationships (overline→title), `mt-2` for moderate (title→metadata), `mt-3` for loose (description→actions).
- In comment/reaction/list areas, is `space-y-3` or `space-y-4` applied to the container? Comments with zero gap between cards look broken.
- Are form elements (inputs, buttons) separated from their labels and from each other? `space-y-4` minimum for form field groups.

**Cross-component spacing conventions:**
- Page-level sections: `space-y-8` (standard for all views)
- Within a card: content groups use `space-y-4`
- Grid of cards: `gap-4` (standard)
- Section heading + content below: heading row should have `mb-4` or `mb-6` before the content grid

**What to avoid:**
- Recommending chaos for its own sake — composition should serve readability
- Overlapping that creates confusion about interactive boundaries
- Density that overwhelms or whitespace that feels empty rather than intentional
- Elements that visually "touch" — headings flush against cards, buttons flush against text, comments with no gap between them

### 2. Typography

Text is the primary interface. Small typographic choices create disproportionate impact.

**What to look for:**
- Is the type hierarchy clear? (titles > subtitles > body > metadata > micro)
- Are font weights used meaningfully? (Use the weight range deliberately — not everything should be semibold)
- Is letter-spacing (`tracking`) appropriate? (Tight for large headings, open for uppercase labels)
- Are line lengths comfortable? (45-75 characters for body text)
- Do numeric values use tabular figures where alignment matters? (tables, counters)
- Could a well-placed text-transform (uppercase, small-caps) add structure?

### 3. Color & Contrast

The existing palette is carefully tuned. Evaluate how well the implementation uses it.

**What to look for:**
- Is the accent color (`--ha-accent`) used sparingly for high-signal moments, or scattered everywhere?
- Do status colors map consistently to their semantics? (emerald=success, red=danger, accent=info, amber=warning)
- Are background layers creating depth? (bg > surface > card creates visual stacking)
- In dark mode, are elements distinguishable? (Many dark-mode issues come from `--ha-surface` and `--ha-bg` being too similar)
- Are opacity/alpha values intentional? (`/10`, `/20`, `/30` for subtle tints — not random)

### 4. Shadows & Depth

Shadows define the spatial relationship between layers. This project uses a distinctive deep, diffused shadow style.

**What to look for:**
- Is the existing `--ha-card-shadow` applied consistently?
- Could additional shadow layers create more convincing depth? (e.g., a subtle inset shadow for form inputs in focus state)
- Do elevated elements (modals, dropdowns, toasts) have appropriately stronger shadows?
- Are shadows adjusted for dark mode? (Dark backgrounds need higher-opacity, warmer shadows)
- Does hover state add a lift effect? (The existing slight `translateY` pattern)

### 5. Borders & Dividers

Borders carry visual weight. The question is always: does this border *earn* its place?

**What to look for:**
- Could a change in background color replace a visible border? (A surface-color shift is quieter than a line)
- Are border colors consistent with the token system? (`--ha-border`, `--ha-card-border`)
- Are there unnecessary double-borders? (Card inside a bordered section creates visual noise)
- Could a decorative accent border add character? (A 2px left-border in accent color on a feature card)

### 6. Transitions & Motion

Animation should feel like a natural part of the interface, not a decoration bolted on.

**What to look for:**
- Do interactive elements respond to hover/focus? (Color shift, subtle scale, shadow change)
- Are transitions timed consistently? (The project uses a short duration for interactions, a longer one for entrances — see the CSS)
- Could staggered reveals improve a list or grid? (The sidebar already does this with `animation-delay`)
- Is there scroll-triggered animation that would feel natural here?
- Are state changes (loading, success, error) animated rather than instant?
- Is `prefers-reduced-motion` respected?

### 7. Micro-Details

The last 5% of polish that separates "looks good" from "feels right."

**What to look for:**
- Icon sizing and alignment within text or buttons (vertically centered? optically balanced?)
- Consistent rounding language (a larger-radius card containing a medium-radius input is intentional; a tiny 4px-radius element inside would break the language)
- Cursor states (pointer on clickable elements, not-allowed on disabled)
- Selection/highlight colors (::selection styling matching the brand)
- Scrollbar styling (if visible, does it match the theme?)
- Print styles (if applicable)

## Workflow

### Step 1: Identify Changed Surfaces

```bash
git diff main...HEAD --name-only | grep -E "(views|components|assets)"
```

### Step 2: Screenshot in Browser

For each changed page/component, take screenshots in both light and dark mode at desktop width, plus 375px mobile.

```bash
agent-browser open https://<app-host>/<page>
agent-browser wait --load networkidle
agent-browser screenshot /tmp/ui-polish-<name>-light.png
```

Toggle dark mode, screenshot again.

### Step 3: Evaluate Against Dimensions

Score each dimension as:
- **Strong** — intentional, well-executed, adds character
- **Adequate** — functional, no issues, but not elevating
- **Weak** — missing opportunity, default/generic feeling
- **Broken** — actively detracting from the experience

### Step 4: Produce Review

## Output Format

```
## UI Polish Review — <branch or component name>

### Spatial Composition: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### Typography: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### Color & Contrast: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### Shadows & Depth: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### Borders & Dividers: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### Transitions & Motion: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### Micro-Details: <Strong|Adequate|Weak|Broken>
- <observation and specific recommendation>

### CSS Architecture
- <any patterns that should be extracted to ha-* classes>
- <any inline Tailwind that's gotten unwieldy>

### Screenshots Reviewed
- <list of pages/viewports/themes tested>
```

### Step 5: Ask Before Fixing

Present the review and ask: "Want me to apply these fixes?" For each recommendation, indicate the effort level (one-liner, moderate, significant) so the user can cherry-pick.

## What This Skill Is NOT

- **Not a functional review** — that's `ux-review` (flow, clarity, accessibility)
- **Not a QA pass** — that's `qa-review` (edge cases, boundary conditions)
- **Not a security audit** — that's `security-review`
- **Not about building from scratch** — this reviews and refines existing UI

This skill is about the *feel*. The difference between a component that works and one that someone pauses to appreciate.
