# Move — Code Review Rubric

The standard set every review (human or Codex) applies **up front**, so recurring
defect classes are caught on the first pass instead of round 5. Derived from
`AGENTS.md` §1. Items marked **[cop]** / **[spec]** are already mechanically
enforced — flag only genuine escapes; items marked **[review]** need judgement.

## Architecture & layering
- **[spec] Business logic lives in `app/actions/`**, never in models or
  controllers. Models = associations/validations/scopes only; controllers =
  authorize → call action → pattern-match → render (no transactions, no
  multi-step persistence). Mutating domain controllers must not call
  `save!`/`create!`/`update!`/`destroy!` directly — go through an action.
- **[spec] Actions are railway-typed** — a `Domain::Verb < BaseAction` whose
  `#call(named:)` returns `Success`/`Failure` (Dry::Monads), with the
  archived-Move guard (`yield ensure_writable(move)`) first on a mutating action.
- **[spec] Side effects via events** — emit `domain.verb` with
  `Rails.event.notify` from the action; never `after_commit`/model callbacks for
  cross-cutting work. Events come from actions (audit infra excepted).
- **[review] Multi-tenancy via Apartment**, auth via Rodauth — never hand-roll
  subdomain/`Current.organization`/`organization_id` scoping or auth tables.

## Correctness traps (have bitten us)
- **[cop] No broad `rescue`** (`rescue StandardError`/bare) in core logic — it
  hides bugs. Only trust-boundary best-effort rescues (subscriber/broadcast §1 #4,
  advisory call) may opt out per-site with `# rubocop:disable Move/BroadRescue --
  <reason>`. Core domain logic rescues specific error classes.
- **[cop] Aggregate in SQL, not Ruby** — no `pluck(...).<reducer>`,
  `to_a.<reducer>`, `select { }.count`. Use `count`/`sum`/`minimum`/`maximum`/
  `group(:x).count`/`exists?`/`pick(Arel.sql(...))`.
- **[review] Coerce `Arel.sql` aggregate outputs** (`&.to_i`/`&.to_d`) — untyped
  casts return **strings** → `"9" > "10"` lexical bug (#283).
- **[review] Phase/state guards live in the shared action**, not just the
  controller/UI — a stale form or MCP/direct call must hit the same guard
  (#290/#293). Atomic multi-record writes; a secondary-cleanup failure must not
  hide the primary effect or its restore affordance (#291).
- **[review] Param allow-list ≠ persisted** — Box/Item actions re-slice to their
  own ATTRS/kwargs; a new field needs adding there too, or it silently saves nil.
- **[review] Selection-only vocabulary** — categories/tags/rooms are picked from
  the Move's managed set; reject out-of-Move ids.

## Live updates & views
- **[review] No JS polling** — reflect server state over ActionCable/Turbo Stream
  broadcasting; a broadcast must never break its emitter (rescue/job).
- **[review] Phlex pitfalls** — no inline `on*` handlers (use Stimulus
  `data-action`); boolean-`false` attrs render as nothing (use `"false"`); Turbo
  ignores a non-redirect 200 on form submit.

## Security & data
- **[review]** ActionPolicy authorize every action; never widen a default scope to
  expose soft-deleted/other-tenant rows; no secrets/tokens in code; Prawn user
  text needs a Unicode TTF.

## Tests & seeds
- **[review]** Cover every rendered view branch (a request spec can miss a Phlex
  branch that never renders — live-verify). New user-facing surface ⇒ seed data
  across its meaningful states (idempotent, production-guarded).
