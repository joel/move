# UX Conventions

Behavioral / interaction conventions for Move — the counterpart to the visual
design system (Phase D0 tokens / Google Stitch). **Phase D0 governs how things
*look*; this doc governs how they *behave*:** defaults, ordering, state coverage,
focus, and what happens *after* a user acts.

The goal is **coherence** — an interaction decided once and applied on every
surface, so the app stops accumulating small irritating inconsistencies (a new
record hidden off-screen, an alphabetical sort no one needs, a facet with nothing
behind it, a search box that forgets what you just did).

> **Living doc.** Every UX papercut we find becomes a rule here — the
> "papercut → rule" loop, the same philosophy as turning recurring code defects
> into cops (`lib/rubocop/cop/move/`). Don't re-litigate a settled rule per
> feature; reference it.

## How to use this

- **Plan-time:** the `/execution-plan` design pass has a UX/interaction step that
  walks the [planning checklist](#planning-checklist-per-user-journey--action) for
  every user journey the change touches. The `code-architect` blueprint must
  encode the answers (default sort, post-action behaviour, every state).
- **Review-time:** the key rules are mirrored in `AGENTS.md` so the `/code-review`
  CR loop (its CLAUDE.md-compliance agents) flags violations automatically;
  UI-heavy changes also get a focused **UX-critic** agent pass against this doc as
  the rubric (there is no official UX-review plugin — see [Enforcement](#enforcement)).
- **Live:** verify the journey in `/product-review` (real browser) — these rules
  are about runtime behaviour, which unit/system specs do not catch.

## Core principles

1. **Make the result of an action immediately visible.** After create / edit /
   move, the affected item must be findable without hunting — insert it where the
   user is looking (its sorted position, or the top when order is recency),
   scroll to it, and/or briefly highlight it, plus a confirmation toast that links
   to it. Never silently append off-screen.
2. **Default to the most *useful* order, not the most convenient.** Insertion
   order and alphabetical are rarely what the user needs. Choose the order that
   serves the task: recency for activity, weight/size for packing & loading
   decisions, frequency/count for facets, priority for work queues. Make the
   active sort visible and changeable.
3. **Hide what doesn't earn its place.** Don't render zero-value chrome: empty
   facets, tags with no attached records, zero-count filters, always-blank
   columns. Every element must help the user decide or navigate.
4. **Remember the user's context.** Prefer the user's last useful input/result
   over a generic placeholder or a reset — recent searches, last-used room, last
   filter. Persist it and offer it.
5. **Cover every state, deliberately.** empty / sparse / loading / processing /
   success / error / failed — design each. (The Design Spec already requires this
   for visuals; it applies to behaviour too.) An empty state is an invitation to
   act, not a dead end.
6. **Preserve focus and scroll.** After an action or a live (Turbo Stream) update,
   keep the user where they were, move focus to the natural next control, and
   never yank scroll to the top on a partial update.
7. **Name actions by their effect, consistently.** The verb on the control matches
   the toast that confirms it (Publish → "Published"). Same concept, same word,
   everywhere (per the `frontend-design` writing guidance).

## Rules (seeded from real papercuts)

These are concrete applications of the principles above. Add a row whenever a new
papercut is found.

| Surface / action | Rule | Principle |
|---|---|---|
| Add a box (`/boxes`) | The new box lands where the user can see it — at its sorted position with a scroll-to + transient highlight (or at the top when order is recency); never silently appended off-screen. | 1 |
| Boxes list — default order | Order by the most decision-useful key (e.g. weight/size for packing & loading), not insertion order. Surface the active sort and let the user change it. | 2 |
| Tag / facet list (`/boxes`) | Show only tags with ≥ 1 attached box; order by count/weight (most-used first), not alphabetically. | 2, 3 |
| Search (`/search`) | Empty project → placeholder examples. Once the user has run a successful search, show the most recent successful search(es) in place of the static placeholders. | 4, 1 |

## Planning checklist (per user journey / action)

For each action or surface the change touches, answer these — and record the
answers in the issue plan and the architect blueprint:

- **After the action:** Where does the user land? Is the new/changed item visible
  without scrolling? Where is focus? Is there a confirmation that links to it?
- **Default ordering:** What is the most useful order for this task? Is the active
  sort visible and changeable?
- **States:** What shows for empty / sparse / full / loading / processing / error?
  Is any element useless in one of those states (then hide it there)?
- **Memory:** Does the surface remember the user's last useful input/result, or
  reset to a placeholder?
- **Consistency:** Does an equivalent surface already solve this? Match it —
  coherence beats local cleverness.
- **Signal-to-noise:** Does every rendered element help the user decide or
  navigate? Cut the rest.

## Enforcement

There is **no official Anthropic UX-review plugin** (the official design tools are
`frontend-design` for *visual* generation and `figma` for design-file import —
neither reviews interaction/UX). So UX is enforced through the tools we already
have:

- **Plan-time:** the `/execution-plan` design pass UX step (this checklist).
- **Review-time:** mirror the key rules into `AGENTS.md` so `/code-review`'s
  CLAUDE.md-compliance agents flag violations; for UI-heavy changes, run a focused
  **UX-critic** agent (an `Agent` call / `feature-dev:code-reviewer`) with **this
  doc as the rubric** — no bespoke skill required.
- **Live:** verify the journey in `/product-review`.
- **Audit:** periodically run a cross-surface UX audit (one agent per surface,
  checking against this doc) to find drift in one pass and backlog it, rather than
  one frustration at a time.
- **Feedback loop:** every new papercut → add a row to [Rules](#rules-seeded-from-real-papercuts);
  if it recurs, mirror it into `AGENTS.md` so review enforces it.

## Relationship to other docs

| Layer | Concern | Source of truth |
|---|---|---|
| Visual (look) | palette, type, spacing, radius, components | Phase D0 tokens / Google Stitch (`AGENTS.md` § Design) |
| Behavioural (feel) | defaults, ordering, states, post-action, focus | **this doc** |
| Copy (words) | labels, empty/error voice, action naming | `frontend-design` writing guidance |
