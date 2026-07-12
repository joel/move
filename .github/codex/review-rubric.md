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
- **[review] Client-side gesture/interaction state machines** (pointer tracking,
  drag/swipe, optimistic UI) — check the interleavings, not the happy path:
  external close/reset mid-gesture (an exclusivity claim from another instance,
  tap-away dismissal, a Turbo Stream replacing the element); a pointer lost
  without a terminal up/cancel; stale time-derived values (velocity read after a
  still hold); ghost-click suppression must be time-bounded, never a latch;
  keyboard/AT must reach gesture-revealed controls (and focus moving on must
  restore state); the enabling breakpoint flipping while active;
  `turbo:before-cache` snapshotting mid-state. Every terminal path (own release,
  external close, teardown) revokes the tracking the gesture start claimed (#602).

## Security & data

Threat-model checklist — this repo is **open source**, so assume an attacker has
full source access. Full trust-boundary map + per-control file pointers in
[`doc/project/security-model.md`](../../doc/project/security-model.md); the
dedicated pass is `/execution-plan` Step 5d + the scheduled `Security Audit`
workflow.

- **[review] Tenant isolation** — every query resolves in the **correct Apartment
  schema**; AR lookups placed *after* an `Apartment::Tenant.switch` block run in the
  wrong schema unless re-wrapped; signed Turbo Stream names must derive from a
  tenant-unique uuid (that signed name **is** the channel auth boundary); never
  widen a `default_scope` to expose other-tenant or soft-deleted rows.
- **[review] Authorization / IDOR** — ActionPolicy `authorize` on every action;
  `authorized_scope` gates row visibility; reject out-of-Move ids (selection-only
  vocabulary — categories/tags/rooms); phase/state **and ownership** guards live in
  the **shared action**, not just the controller/UI — a forged param, stale form, or
  direct MCP call must hit the same guard. Gate on the **validated** result, not the
  raw param (cf. the forged `source_media_id` finding).
- **[review] Authentication** — no Rodauth bypass; verify-before-login; account
  status checks; remember-me scoped to the org subdomain (never apex); single-use
  session-handoff tokens; WebAuthn RP id = apex; social sign-in must not skip the
  account-creation guards.
- **[review] Injection & input** — strong-params re-sliced inside the action (a new
  field must be added to the action's own ATTRS/kwargs); no SQL injection via
  `Arel.sql` string interpolation; no new shell/command injection — the 5
  Brakeman-ignored `system(...)` sites are **dev-only `bin/cli`** tooling and must
  stay unreachable from any web request.
- **[review] File upload & external egress (SSRF/data leak)** — image uploads keep
  the magic-byte sniff + size cap (`Media::MAX_IMAGE_BYTES`) + Move-scoped signed-id
  handshake; user text/images sent to external AI providers
  (recognition/embedding) is an **egress boundary** — no secret/PII leakage, per-Move
  BYO keys stay encrypted at rest.
- **[review] Secrets** — no secrets/tokens/keys in code, fixtures, or logs;
  per-Move API keys are encrypted attributes; prod secrets come from
  Doppler/credentials only.
- **[review] Output safety** — Phlex auto-escapes, but audit every
  `raw`/`html_safe`/`sanitize`/`unsafe_raw` for XSS; Rodauth forms must carry
  context (token/account) via **hidden fields**, never trust a client-supplied
  tenant/account; Prawn user text needs a Unicode TTF (AFM fonts raise on accents/
  emoji).

## Tests & seeds
- **[review]** Cover every rendered view branch (a request spec can miss a Phlex
  branch that never renders — live-verify). New user-facing surface ⇒ seed data
  across its meaningful states (idempotent, production-guarded).
