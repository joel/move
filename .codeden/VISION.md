# Vision

Move is a calm, collaborative moving-inventory manager. People pack things into numbered
boxes, snap a photo and let AI list the contents, find anything across the whole move,
print QR labels, and tick items off as they unpack. It is a multi-tenant Rails 8.1 app
(Phlex + Hotwire, no Node), open source at joel/move, deployed to https://move-easy.org.
The factory scores every piece of work against this file.

## Goals
- Make the core loop (pack → capture → review → search → unpack) fast, reliable and
  pleasant on a phone, with every state covered.
- Keep recognition runs trustworthy: a failed run leaves no partial inventory, and review
  is quick (Mark / Ignore, move-wide queue).
- Close open product gaps from the issue tracker (household roles, leave/transfer of
  ownership, find list, insurance exports) without growing the surface needlessly.
- Pay down operational risk: green CI on `main`, current dependencies, working backups,
  a self-healing pipeline that stays safe.
- Move off Google Stitch as the design source. Trial Claude Design as the candidate
  replacement; no tool is picked yet. Meanwhile DESIGN.md, the Phase D0 tokens and the
  `Ui::*` kit in Lookbook are the reference.

## Target users
- Households moving home (solo or shared): need to know what is in which box, find an
  item quickly, and unpack without losing track.
- Organisation members with roles (owner, admin, member): need the right access and
  nothing more, in their own tenant.
- AI clients using the MCP assistant: need a stable, safe API to query and update a move.

## Principles
- Small, well-tested, single-purpose changes; one issue per PR (`Closes #<n>`).
- Business logic in `app/actions/` (`Domain::Verb < BaseAction`, Dry::Monads,
  `domain.verb` events); models persistence-only; controllers thin.
- Tenancy only through Apartment (schema per tenant); never hand-rolled scoping.
- Live updates through ActionCable / Turbo Streams; no client polling.
- Aggregate and filter in the database, not in Ruby.
- Respect Packwerk boundaries; reach other domains only through their public API.
- Every new or changed method carries inline RBS; Steep stays green.
- Follow the UX rules in `doc/project/ux-conventions.md`: visible results, useful default
  order, no zero-value chrome, remember context, cover every state.
- Use well-known libraries over hand-rolled code.
- Keep the MCP API and public URLs stable.

## Out of scope
- New infrastructure or vendors (hosting, payments, analytics, tracking) without a human ask.
- Client-side polling, Node toolchains, SPA frameworks.
- New customer-facing screens with no agreed design (ask first; never invent a screen).
- Picking or wiring up a design tool, or new work that pushes designs back to Stitch.
- Rewriting working subsystems for style alone, or speculative features (YAGNI).
- Seeding or editing production data; minting auth for real users.
- Toggling repository variables or secrets (self-healing kill switch, autonomy flag).
- Anything that copies Sentry event data into issues, PRs, prompts or logs.

## Quality bar
- Every behaviour change comes with tests (TDD where practical); request specs cover every
  view branch, `:js` specs where behaviour is JS-only.
- Pre-commit gates pass: RuboCop (incl. `Move/*` cops), erb_lint, Steep, Packwerk,
  Brakeman, bundle-audit, unit and system specs, `structure.sql` up to date.
- CI `lint` and `test` are green on the HEAD sha before merge (HEAD is a code commit).
- Live verification via `/product-review`, including the full auth journey when anything
  near auth changes.
- Codex review converged: `codex-review-state:v1` with `has_any_findings:false` on HEAD.
- Docs and diagrams updated for cross-cutting changes; DESIGN.md for token or `Ui::*`
  changes; seeds extended for new surfaces.
- No `[skip ci]` style markers in commits or squash messages.

## Protected areas
Paths (globs in backticks) and topics that always need a human. The factory never merges
changes that touch them; they go to your inbox.
- `app/misc/**` (Rodauth, WebAuthn, sessions)
- `**/auth/**`
- `app/controllers/*session*`, `app/controllers/google_one_tap_sessions_controller.rb`,
  `app/controllers/invitation_acceptances_controller.rb`
- `packs/session_handoffs/**`, `packs/accounts/**`, `packs/organizations/**`,
  `packs/move_integration_tokens/**`, `packs/terms/**`
- `config/initializers/apartment.rb`, `config/initializers/*rodauth*`,
  `config/initializers/content_security_policy.rb`
- `db/migrate/**`, `db/structure.sql`, `db/*_structure.sql`, `**/migrations/**`
- `config/deploy.yml`, `.kamal/**`, `Dockerfile`, `config/credentials*`
- `.github/workflows/**`, `.github/codex/**`, `script/self_healing/**`
- `config/brakeman.ignore`, `.rubocop.yml`, `lib/rubocop/cop/move/**`, `Steepfile`,
  `package.yml`, `packs/*/package.yml`
- `AGENTS.md`, `CLAUDE.md`, `.codeden/**`, `LICENSE`
- authentication, sessions, passkeys, account deletion, tenant create/drop
- secrets, Doppler, Cloudflare, production data and deploys
- security advisories and anything in the security model
- payments, licensing, privacy and terms text
- releases and tags
- choosing the design tool and changing the design source of truth
