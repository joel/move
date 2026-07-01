# AGENTS.md

This document provides instructions and protocols for AI Agents interacting with this repository. **Follow these guidelines strictly to ensure project consistency.**

## 1. Context & Environment

- **Live Testing:** Use the `agent-browser` tool (and the `/product-review` skill) to verify changes visually and functionally.

- **GitHub CLI:** Always `unset GITHUB_TOKEN` before running `gh` commands. The environment may have a stale token that causes `HTTP 401: Bad credentials` errors. The `gh` CLI falls back to its own auth store when the env var is unset.

- **Ruby version manager:** This project uses **mise**. Prefix Ruby/Rails commands with `mise x --` (e.g. `mise x -- bundle exec rspec`) so the project's Ruby (`.ruby-version`) is used.

- **URLs:** Local development (via `bin/cli`): `https://move.move-easy.docker` (mail at `https://mail.move-easy.docker`). Production: `https://move-easy.org` (apex/login; org subdomains `<slug>.move-easy.org`), behind Cloudflare (Full Strict, Origin CA wildcard cert served by kamal-proxy).

### Design source of truth (Google Stitch)

**The visual design lives in Google Stitch, reached through the Stitch MCP server — not in the codebase or your imagination.** Before building or changing any **customer-facing** screen, you MUST open the real design and build against it. Never guess a layout, colour, spacing, radius, or type value.

> **Exception — the `/execution-plan` design pass.** When UI work runs through the
> `execution-plan` skill, its design pass intentionally **inverts this rule**: the
> `frontend-design` plugin *leads* the visual direction and Stitch becomes a
> *secondary reference*, with the settled design pushed back into Stitch afterward.
> Everywhere else (and for the build substrate — Phase D0 tokens + Phlex components),
> Stitch remains the source of truth as described here. See
> `.claude/skills/execution-plan/SKILL.md` § "Design Phase".

- **Project:** `Move Design` → `projects/13869765800416404511` (a separate `Move Inventory Manager` project also exists — do not confuse them).
- **Design system (tokens):** `mcp__stitch__get_project name=projects/13869765800416404511` → `designTheme.designMd`. This is the authoritative colour/typography/spacing/radius/component sheet. It is mirrored in `doc/phases/Phase D0 - Design Foundation.md` and consolidated for quick reference in [`DESIGN.md`](DESIGN.md) (the flat human reference for tokens + the `Ui::*` component library; keep it in sync per §7).
- **Screens:** `mcp__stitch__list_screens projectId=13869765800416404511`, then `mcp__stitch__get_screen name=projects/13869765800416404511/screens/<id>` for the HTML + screenshot. (`list_projects`/`list_screens` outputs are large — they spill to a file you can `jq`.)
- **Canonical screen ↔ phase ↔ Design-Spec map:** `doc/phases/README.md` §2.
- **Palette rule:** the **"Refined Palette"** variants are canonical for surfaces/accent; the Material-3 token set is the semantic system for state colours. Prefer `… - Refined Palette` screens. See `doc/phases/DESIGN-DISCREPANCIES.md` §PALETTE.

**Workflow for any UI work:**
1. Open the canonical Stitch screen(s) for the surface and read the HTML + screenshot.
2. Build with Phlex components + the Phase D0 design tokens — no magic values.
3. Reproduce **every** state the Design Spec lists (empty, loading, processing, failed, error, dark).
4. Live-verify with `/product-review` and compare screenshot-to-screenshot against Stitch.

**If a screen you need does not exist in Stitch, STOP — do not invent it.** Either generate it with `mcp__stitch__generate_screen_from_text` (use `designSystem=<project system id>`, dark-first, the brand prompt in the relevant phase file) and record the new `screens/<id>` in `doc/phases/README.md`, or request it from the user/product. Log the gap and remediation in `doc/phases/DESIGN-DISCREPANCIES.md`. As of this writing **all 16 Design-Spec screens have a Stitch design** (the previously-missing A1, E2, E3, and F3 screens were created in the Stitch UI — see `DESIGN-DISCREPANCIES.md`), so no phase is design-blocked.

**Design-led phase plan:** `doc/phases/` re-organises the v0.2 work around screens so each customer-facing surface ships against a real design. `Phase D0` (design foundation) must land before any other UI phase. The domain-led companion plan is `doc/ai/v0.2/prompts/`.

### UX / interaction conventions (MUST follow for user-facing changes)

Phase D0 / Stitch govern how surfaces **look**; these govern how they **behave**.
The full rubric (principles, rules table, planning checklist) lives in
[`doc/project/ux-conventions.md`](doc/project/ux-conventions.md) and is applied at
plan-time by the `/execution-plan` design pass. The non-negotiable rules — review
(`/code-review`) flags violations on any user-facing change:

1. **Make the result of an action visible.** After create/edit/move, the affected
   record must be visible without scrolling (insert at its sorted position with a
   scroll-to + transient highlight, or top when order is recency) plus a linking
   confirmation toast. **Never silently append a new record off-screen.**
2. **Default to the most *useful* order, not insertion or alphabetical.** Choose the
   order that serves the task (recency / weight / count / priority); make the active
   sort visible and changeable.
3. **Hide what doesn't earn its place.** No zero-value chrome in **read-only**
   surfaces — empty facets, zero-count filters, always-blank columns. (Does **not**
   apply to *selection* surfaces: a picker/management list keeps unused options
   selectable; order them most-used-first instead.)
4. **Remember the user's context.** Prefer the user's last useful input/result over a
   generic placeholder or reset (recent searches, last-used room/filter).
5. **Cover every state deliberately** (empty / sparse / loading / processing / error)
   and **preserve focus + scroll** across actions and Turbo Stream updates.

New papercuts become a rule in `ux-conventions.md`; if it recurs, mirror it here.

### Architecture & engineering conventions (MUST follow)

These are non-negotiable for all domain work. Do not reinvent these wheels.

1. **Multi-tenancy → use the Apartment gem.** Do **not** hand-roll subdomain
   resolution, `Current.organization` scoping, or `organization_id` filtering.
   Tenancy is PostgreSQL **schema-per-tenant** via
   [`ros-apartment`](https://github.com/rails-on-services/apartment): each
   Organization is a tenant (schema); `Apartment::Elevator::Subdomain` resolves
   the tenant from the subdomain; shared models (Rodauth/user auth tables, the
   Organization registry) live in the `public` schema via `excluded_models`.
   Create/drop tenants with `Apartment::Tenant.create/drop`; scope work with
   `Apartment::Tenant.switch(name) { … }`. Config in `config/initializers/apartment.rb`.

2. **Business logic → `app/actions/` (never in models).** Models stay
   persistence-focused (associations, validations, scopes). Controllers stay thin
   (authorize → call action → pattern-match → render). Every domain operation is a
   `Domain::Verb < BaseAction` using `Dry::Monads` result/do notation and emitting
   a `domain.verb` `Rails.event`. Full reference + templates in
   [`app/actions/AGENTS.md`](app/actions/AGENTS.md). Pattern mirrors the sibling
   `catalyst` project and https://github.com/joel/trip/tree/main/app/actions.

3. **Live-test authentication after every change.** Auth is fragile (passwordless
   Rodauth + remember-me + the Apartment elevator). Before pushing, run the
   **Runtime Test Workflow** (§5 / `/product-review`) and explicitly verify the
   full auth journey — create account, sign in, sign out, sign back in — works
   end to end in the running app. A green test suite is **not** sufficient.
   Auth-layer reference + hard-won gotchas (stale-session-after-DB-reset,
   verify-before-login, forms dropping query params, remember-me) live in
   [`app/misc/AGENTS.md`](app/misc/AGENTS.md).

4. **Live updates → ActionCable / Turbo Streams. JS polling is FORBIDDEN.** Never
   poll the server from the client (`setInterval` + `fetch`, a Stimulus poller, a
   refresh meta tag, etc.) to reflect server-side progress or state. Push it over
   **ActionCable** using turbo-rails Turbo Stream broadcasting — the Rails-default
   mechanism (Solid Cable in prod; `async` in dev). Reference impl: the search
   indexing progress (#239) and the capture session panel (#241) — an action/job
   emits a `Rails.event`, a subscriber re-renders the Phlex view via
   `ApplicationController.render(view, layout: false)` and
   `Turbo::StreamsChannel.broadcast_replace_to([record, :scope], target:, html:)`,
   and the page subscribes with `turbo_stream_from`. Conventions/gotchas:
   - **Signed stream names are the auth boundary** — derive the stream from a
     tenant-unique record (a uuid); no per-user channel auth is needed. Set
     `config.action_cable.allowed_request_origins` for the dev **org-subdomain**
     host and the prod `*.move-easy.org` hosts, or the WS handshake is rejected.
   - **A broadcast must never break its emitter.** A `Rails.event` subscriber runs
     synchronously inside the emitting action, so wrap render/broadcast in a
     `rescue` (or enqueue a job) — a broadcast failure must not fail the action.
     Such a broad `rescue` is the *only* sanctioned use of `rescue StandardError`;
     it is flagged by the **`Move/BroadRescue`** cop and must opt out per-site with
     `# rubocop:disable Move/BroadRescue -- <reason>` so the exception stays
     conscious. Core domain logic must rescue specific error classes (#293).
   - turbo-rails' `turbo.min.js` already bundles `@rails/actioncable`; add
     `ApplicationCable::Connection`/`Channel` (Turbo::StreamsChannel needs them).
   - The one remaining JS poller (`recognition_poller_controller.js`, recovery
     surface) is being migrated to cable (#244) — do not add new ones.

5. **Aggregation/filtering → the database, never the application layer.** Do
   **not** load rows into Ruby to compute what SQL can: no
   `pluck(...).map/min/max/sum/size`, no `.select { … }.count`, no
   `.to_a.sum(&:x)`, no Ruby `group_by` for counts. Use SQL — `minimum`/`maximum`/
   `sum`/`count`/`average`, `pick(Arel.sql("MIN(x), MAX(x), COUNT(*)"))`,
   `group(:x).count`, `where(...).count`, `exists?`, `distinct`. Let Postgres
   return the answer (one row), not the rows. **Coerce `Arel.sql` aggregate
   outputs** (`&.to_i` / `&.to_f`): untyped casts come back as **strings**, so a
   raw `MAX(number::bigint)` compares lexically (`"9" > "10"`) — the exact bug
   behind `LabelPrintsController#range_bounds` and `Boxes::Create#next_number`
   (#283). Loading-and-computing in Ruby is an O(N)-for-O(1) regression; flag it
   in review. The unambiguous shapes (`pluck(...).<reducer>`, `to_a.<reducer>`,
   `select { … }.count`) are enforced by the **`Move/DatabaseAggregation`** cop;
   `group_by` is not copped (it is legitimate on already-in-memory collections).

6. **Domain boundaries → Packwerk, never ad-hoc cross-domain reaching.** Each
   domain is being carved into a `packs/<domain>/` package that declares its
   dependencies and exposes a minimal **public API** (a public model in
   `app/public/`; a public entry-point action stays in `app/actions/` marked
   `# pack_public: true`). A pack may only reference packs it lists in
   `dependencies`, only their public constants (`enforce_privacy`), only packs that
   list it in `visible_to` (`enforce_visibility`), and only its own/lower
   architecture `layer` (`enforce_architecture`). Don't reach into another domain's
   internals — depend on its public surface, or extend that surface deliberately.
   The migration is staged (one pack per PR); `packs/labels` is the template. Full
   reference: [`doc/project/packwerk-boundaries.md`](doc/project/packwerk-boundaries.md).

> **These cops live in `lib/rubocop/cop/move/`** (wired via `require:` in
> `.rubocop.yml`, with RuboCop::RSpec specs). They make rules #4/#5 deterministic
> and merge-blocking instead of review-enforced. When a recurring class of defect
> escapes review, prefer adding/extending a cop over re-reminding. The **horizontal**
> (domain) counterpart to these **vertical** (layer) cops is **Packwerk** (rule #6),
> run merge-blocking by the `packwerk` CI job + the overcommit pre-commit hook.

---

## 2. CLI Operations (`bin/cli`)

Pilot the application and infrastructure through the CLI.

### Usage Syntax

`bin/cli COMMAND ACTION [ENV]`

| **Command** | **Description** |
|---|---|
| `app ACTION [ENV]` | Manage the application container. |
| `db ACTION [ENV]` | Manage the database container (migrations, reset, etc.). |
| `mail ACTION` | Manage the local mail service. |
| `storage ACTION` | Manage the local SeaweedFS storage service. |
| `services ACTION [ENV]` | Orchestrate all services together. |
| `tree` | Print a tree of all available commands. |
| `help [COMMAND]` | Describe available commands or one specific command. |

### Parameters

- **ACTION:** Common actions include `start`, `stop`, `build`, `rebuild`, `restart`, `logs`, `connect`, `console`, `reset`.

- **ENV:** Options are `dev` | `development` (default) or `prod` | `production`.

---

## 3. Development Workflow & Quality Control

### Pre-Commit Validation

Prefix Ruby commands with `mise x --`. Run these and ensure they pass before committing — they mirror the CI `lint` and `test` jobs (`.github/workflows/ci.yml`):

1. **Linting:** `bundle exec rubocop` (autocorrect with `bundle exec rubocop -A`) and `bin/erb_lint --lint-all`.

2. **Security:** `brakeman --exit-on-warn --no-progress` and `bundle-audit check --update`. Reviewed, accepted findings live in `config/brakeman.ignore`.

3. **Testing:** `bundle exec rspec spec --exclude-pattern "spec/system/**/*_spec.rb"` (unit) and `TEST_BROWSER=rack_test bundle exec rspec spec/system` (system).

### Git & Overcommit Hooks

The project uses `overcommit`. Commits will fail if the following hooks are not satisfied:

- **Pre-commit:** trailing whitespace, `FIXME` tokens, **RuboCop**, **ErbLint**, **BundleCheck**, **LocalPathsInGemfile**, and **RailsSchemaUpToDate** (the committed `db/structure.sql` must match the migrations — this project is `schema_format :sql`, so there is no `db/schema.rb`).

- **Commit-msg:** capitalized subject, no trailing period, single-line subject, and a line-width limit.

- **Action:** If a hook fails, resolve the issue in the code or commit message before re-committing.

---

## 4. Process & Governance

1. **Issue First:** No work without an existing issue in [move Issues](https://github.com/joel/move/issues). Create one if needed.

2. **Repository:** All code is pushed to [`joel/move`](https://github.com/joel/move). `main` is **protected** — the `lint` and `test` checks must pass before a PR can merge.

### Workflow Steps

1. Read `AGENTS.md` / `CLAUDE.md` to understand current project rules.
2. Create an issue on [move Issues](https://github.com/joel/move/issues) with a detailed plan; add an appropriate label (`bug`, `enhancement`, `cleanup`, `documentation`, etc.).
3. Create a branch from `main` (`feature/*`, `fix/*`, `docs/*`, `refactor/*`).
4. Implement the change with tests (TDD where practical).
5. Run the local review passes — **Code Review** (`/code-review`) and, on
   security-sensitive changes, the **Security Review** (`/security-review`, see
   below) — then the **Pre-Commit Validation** (lint + tests), and make atomic commits.
6. Perform live verification (see **Runtime Test Workflow** / `/product-review`).
7. Push the branch and open a PR with a summary and test plan (`Closes #<issue>`). Wait for the required `lint` and `test` checks.
8. **Wait for and check the Codex automated review** (see below) — proactively, before declaring the work done. Then respond to **every** review comment (human **and** Codex) and resolve each conversation.
9. After the PR is merged to `main` (squash), the **production deploy runs automatically** (see **Deployment**).
10. Tag a release when the change warrants one (see **Release Rules**).

### PR Review Response Rules

> **Review rubric:** [`.github/codex/review-rubric.md`](.github/codex/review-rubric.md)
> is the standard set every review (human or Codex) applies up front, and the
> self-review checklist to run **before** opening a PR — so recurring classes are
> caught on the first pass, not round 5. Architecture items in it are also enforced
> by `spec/architecture/` and the `Move/*` cops.

> **Security review is a dedicated pass, not just a rubric line.** The rubric's
> **"Security & data"** section + the threat model in
> [`doc/project/security-model.md`](doc/project/security-model.md) are the standard
> every security review applies. Because this repo is **open source**, security is
> covered in two places: a **per-change** adversarial pass — `/execution-plan`
> **Step 5d** runs `/security-review` on security-sensitive branch diffs before the
> PR is public — and a **whole-repo** scan, the on-demand `Security Audit`
> workflow ([`.github/workflows/security-audit.yml`](.github/workflows/security-audit.yml)),
> which on findings opens a **fixed-body** `security` issue and fails the run — it
> never republishes the model report (public CI sinks emit only a content-free
> notice; actionable detail lives in the local `/security-review`). Neither blocks
> merge; both are run/triaged as part of the loop.

> **Codex reviews every PR automatically.** `chatgpt-codex-connector[bot]` posts a
> review **a few minutes after the PR is opened** (and re-runs on new pushes or a
> `@codex review` comment). **Always proactively wait for and check the Codex
> review before declaring the work done or handing back — without being asked.**
> Opening the PR is not the end of the loop; the Codex pass is part of it. Check
> with `gh api repos/joel/move/pulls/<PR>/reviews` and `.../comments` filtered to
> `chatgpt-codex-connector[bot]`. If it left inline comments, triage each one
> below; if it only reacted 👍, note that and proceed. After pushing fixes, Codex
> re-reviews — re-check before finishing.

When a PR receives code review comments (human **or** Codex):

1. **Read all comments** using `gh api repos/joel/move/pulls/<PR>/comments`.
2. **Evaluate each comment** — decide whether to act on it, explain why not, or defer to a follow-up issue.
3. **For actionable feedback:** Fix the code, commit, push, then reply explaining what was fixed and in which commit.
4. **For incorrect feedback:** Reply with a clear technical explanation of why no action is needed.
5. **For deferred feedback:** Reply acknowledging the concern and stating which follow-up issue/PR will address it.
6. **Reply to every comment** using `gh api repos/joel/move/pulls/<PR>/comments/<ID>/replies -X POST -f body='...'`. The `<PR>` number is required — omitting it (`gh api repos/joel/move/pulls/comments/<ID>/replies`) returns `HTTP 404: Not Found`.
7. **Resolve every conversation** after replying using the GraphQL `resolveReviewThread` mutation.
8. Never leave review comments unanswered or unresolved.

### Deployment

- `.github/workflows/deploy.yml` deploys to production (`move-easy.org`) via **Kamal** on **every push to `main`** (i.e. every merge).
- Secrets come from **Doppler** (`move/prd`), synced into GitHub Actions secrets. `.kamal/secrets` is gated on `KAMAL_SECRETS_FROM_ENV` (set in the Deploy workflow): **CI** reads the synced env values; a **local** deploy ignores the ambient shell/`.env` and always reads from the Doppler CLI / `config/master.key` — so a stale exported secret can't shadow Doppler (local deploys therefore need Doppler auth). Force a rotated value live with a redeploy (`kamal deploy`); a `kamal app start/stop` only restarts the existing container with its baked-in env.
- Skip a deploy for a given commit with `[skip deploy]` in the commit **subject**. **Beware:** a squash-merge whose body quotes the literal `[skip deploy]` (for example, by referencing this document) will skip the deploy unintentionally.
- **Never use `[skip ci]` / `[ci skip]` / `[no ci]` / `[skip actions]` in commit messages.** GitHub treats them anywhere in the message as a platform-level skip that suppresses **all** workflow runs for the push — including the deploy — and it **cannot** be overridden in workflow YAML. Docs are excluded from CI via `paths-ignore` in `ci.yml`, never via a marker. A `commit-msg` overcommit hook (`ForbidSkipMarkers`) rejects these locally.
- **Recover a skipped deploy** by re-running it manually: `unset GITHUB_TOKEN && gh workflow run Deploy --ref main` (the deploy workflow has `workflow_dispatch`), or from the Actions tab.

#### Squash-and-merge hygiene

Squash merges aggregate the branch's commit messages into the merge commit body
**by default**, which is how stray `[skip ci]` markers reach `main` and skip the
deploy. To prevent it, set the repo to use the PR title + description for squash
commits (one-time, requires admin):

```bash
unset GITHUB_TOKEN && gh api -X PATCH repos/joel/move \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY
```

Then **write a real PR description** — it becomes the squash commit body, so keep
it marker-free and meaningful. At merge time, double-check the squash message
contains no `[skip ci]` / `[skip deploy]`.

#### Database accessory (PostgreSQL 18)

The database is a **Kamal accessory** defined in `config/deploy.yml` (`accessories.db`):
`image: postgres:18`, mounted at `directories: - data:/var/lib/postgresql`.

- **Pinned to `postgres:18`.** `schema_format :sql` dumps and Apartment tenant
  cloning need a `pg_dump` matching the server, so the app image ships
  `postgresql-client-18` and **every** Postgres image (dev `bin/cli`, CI service,
  prod accessory) is pinned to 18. Do not float on `postgres:latest`.
- **Mount the parent, not `/data`.** `postgres:18+` stores the cluster in a
  major-version subdirectory (`/var/lib/postgresql/18/docker`) for `pg_upgrade
  --link`, and refuses to start against an old-style cluster at
  `/var/lib/postgresql/data`. The mount target must be `/var/lib/postgresql`
  (already set for dev and prod).
- **Accessories are not rebooted by an app deploy.** A push to `main` redeploys
  the app but leaves `accessories.db` untouched — image/mount changes to the
  accessory require a manual `kamal accessory` cutover.

##### One-time PG 18 cutover (Kamal 2)

Needed when the prod accessory still runs an old image/layout. **Destroys the
cluster — only safe when there is no data to keep** (back up first otherwise, or
use `pg_upgrade`). Run from a checkout with the merged `deploy.yml`:

```bash
kamal accessory remove db          # stop/remove the old container…
# …then on the db host, ensure the accessory's bind-mounted `data` dir is empty
# (Kamal may leave it): rm -rf the accessory data dir if so.
kamal accessory boot db            # pull postgres:18, init the new layout fresh

# verify
docker exec <db-container> cat /var/lib/postgresql/18/docker/PG_VERSION   # => 18
docker exec <db-container> psql -U move -d move_production -c 'select version();'

# load the schema (creates move_production + cache/queue/cable, loads
# structure.sql, migrates) — or just redeploy; the app entrypoint runs db:prepare
kamal app exec --reuse 'bin/rails db:prepare'
```

Then smoke-test the live auth journey at `https://move-easy.org` and
create a Move on an org subdomain. Order: merge → accessory cutover → `db:prepare`
→ smoke test.

### Release Rules

Run after a PR is merged to `main` and its `main` CI/Deploy run is green.

1. **Sync and verify.** `git checkout main && git pull origin main`; confirm the merge commit is present and CI is green.
2. **Tag convention: SemVer `vMAJOR.MINOR.PATCH`** (e.g. `v0.2.0`). One release per meaningful set of changes.
3. **Idempotent.** If the tag/release already exists, stop — never recreate or overwrite a published release.
4. **Tag + publish in one step** (auto-generated notes from merged PRs/commits since the previous tag):
   ```bash
   unset GITHUB_TOKEN && gh release create vX.Y.Z \
     --repo joel/move --target main \
     --title "vX.Y.Z" \
     --generate-notes
   ```
   `--generate-notes` honours `.github/release.yml`, which **excludes Dependabot / `dependencies`-labelled PRs** — do not re-add them.
5. **Tags do not deploy.** `deploy.yml` triggers on the merge commit (push to `main`), not on tags. A `v*` tag instead triggers the **Release Bug Scan** (`.github/workflows/release-bug-scan.yml`, a read-only Codex scan over the diff since the previous tag) — review its findings and open issues for anything real.

### Workflow Rules

- **Never disable overcommit entirely** (`OVERCOMMIT_DISABLE=1`). When a hook indicates a false positive, skip **only** the specific hook: `SKIP=<HookName> git commit ...` (e.g. `SKIP=RailsSchemaUpToDate`). Add a footnote in the commit body explaining which hook was skipped and why.

- **`RailsSchemaUpToDate` false-positive when editing an already-applied migration** (recurring — D7 & D8): adding a *data-only* preflight/backfill step to a migration that already ran (so its version is in `schema_migrations`) leaves `db/structure.sql` unchanged, but the hook still flags it. Confirm with `bin/rails db:schema:dump` (no `structure.sql` diff), then commit with `SKIP=RailsSchemaUpToDate` and a footnote saying the dump is clean.

- **Migrations that need a new DB capability (extension / accessory image) require a manual accessory cutover BEFORE merge.** A normal deploy runs `db:migrate` but does **not** reboot Kamal accessories, so e.g. a `CREATE EXTENSION vector` migration aborts the prod deploy unless the `db` accessory was first cut over (`kamal accessory reboot db` on the new image; `ALTER DATABASE … REFRESH COLLATION VERSION` if the image's glibc differs). Order: cut over → merge → deploy migrates cleanly. Full runbook + gotchas in `doc/project/new-app-recipe.md`.

- **Do not use `[skip ci]` markers.** CI decides whether to run via `paths-ignore` in `.github/workflows/ci.yml` (`**/*.md`, `.claude/**` are ignored automatically). If a new path should be exempt from CI, add it to `paths-ignore` instead of relying on commit-message markers.

- **Test full user journeys, not just page rendering.** Runtime tests must verify multi-step flows end-to-end (e.g. sign up → verify email → sign in → perform an action → see the result). A page rendering correctly does not guarantee the logic behind it works. If a feature involves events, subscribers, or background jobs, verify the downstream effects actually happen (check emails in the local mail service, check database records).

- **Rails 8.1 `Rails.event` structured events.** Subscribers must respond to `#emit(event)`, not `#call`. The event is a hash: `event[:name]`, `event[:payload]`, `event[:tags]`, etc. Register with `Rails.event.subscribe(subscriber)` and an optional filter block: `{ |e| e[:name].start_with?("prefix.") }`.

- **Shell escaping with `docker exec` + `bin/rails runner`.** Ruby bang methods (`save!`, `find_by!`) break in shell because `!` is interpreted by bash. Use a heredoc redirect instead: `docker exec -i <container> bin/rails runner - < /tmp/script.rb`.

- **Rodauth forms lose query parameters on POST.** If a URL carries query params (e.g. `?token=xxx`), the Rodauth form POST will not include them. Add hidden fields in the Phlex view to carry params through.

- **Pre-fill forms from context, not just params.** When a URL carries context (tokens, IDs) that determines valid input, pre-fill and lock the relevant fields. Never rely on the user to type something the system already knows — mismatches cause silent rejections that look like bugs.

- **A new vendored importmap asset is invisible in dev until `assets:precompile` + app restart** (D9 `vendor/javascript/jsqr.js`). The page's `<script type=importmap>` omits the pin and `asset_path("x.js")` raises `Propshaft::MissingAssetError` even though `Rails.application.assets.load_path.find("x.js")` succeeds — the running Puma memoised Propshaft's manifest at boot. Fix: `docker exec move-app-dev bin/rails assets:precompile` **then** `bin/cli app restart` (both needed). A bare `import x from "pkg"` that 404s silently kills the whole Stimulus controller. **Not a code bug** — prod precompiles at image build. Verify: `document.querySelector('script[type=importmap]').textContent.includes('pkg')`. Full detail in agent memory `product-review-asset-staleness`.

- **Prawn PDFs must embed a Unicode TTF — never render user text with the built-in (AFM) fonts.** Helvetica & co. only encode Windows-1252, so a user-supplied name with accents/CJK/emoji/smart-punctuation raises `Prawn::Errors::IncompatibleStringEncoding` → a 500 (D9 #85). Register a TTF (vendored `app/assets/fonts/NotoSans-*.ttf` via the `PdfFonts` mixin) and `doc.font(...)` before rendering any user text; glyphs the TTF lacks degrade to blank `.notdef` boxes (no crash). Add a spec that renders Unicode + emoji content asserting `not_to raise_error`.

- **A `[skip ci]` marker in a commit is forbidden here** (it skips the deploy via squash-merge). The `/execution-plan` skill's Step 7 still suggests `[skip ci]` for docs — **ignore that**; CI already path-ignores `**/*.md` and `.claude/**` via `paths-ignore`, so docs commits need no marker. (See §4 Deployment.)

- **A docs-only commit at the PR tip leaves the PR `BLOCKED`** (recurring — D10 #90). Branch protection requires the `lint` + `test` contexts **on the HEAD sha**, but `ci.yml` path-ignores `**/*.md`, `doc/**`, `.claude/**`, so a docs-only HEAD never produces those contexts → `mergeStateStatus: BLOCKED` forever (no admin override needed to *avoid*, just don't end on docs). **Keep a code-touching commit at HEAD**: commit code last, or fold the trailing docs into the code commit (`git reset --soft <code-sha>` → `git add <docs>` → `git commit --amend`, then `git push --force-with-lease`; verify the net tree is unchanged with `git diff <backup> HEAD`). Same root cause as a *fully* docs-only PR (admin-merge those — see agent memory `docs-pr-required-checks-blocked`), but here only the tip is docs.

- **A `#<issue>`-prefixed commit subject with NO body is treated as empty by git** and fails the `EmptyMessage` commit-msg hook. Git's default `commentChar` is `#`, so a message that is a single `#…` line gets stripped to nothing. Multi-line messages (subject + body) are fine — it only bites subject-only commits like `#91 Link PR`. Fix: add a body, or commit with `git -c core.commentChar=";" commit -m "#91 …"`.

- **New Tailwind utilities are stale in dev until the CSS is rebuilt** (D10 — `text-left`, arbitrary values like `blur-2xl`/`border-4`). The CSS analogue of the importmap gotcha above: `bin/cli app rebuild` does **not** recompile Tailwind, so a class only used in a new view is absent and the element silently keeps the inherited style. Fix: `docker exec move-app-dev bin/rails tailwindcss:build` (regenerates `app/assets/builds/tailwind.css`); if you also ran `assets:precompile`, `rm -rf public/assets` afterward so dev serves the fresh build (precompiled `public/assets/.manifest.json` masks it), then `bin/cli app restart`. **Not a code bug** — prod precompiles at image build. Verify a class compiled: check `getComputedStyle(el)` in the browser, not `document.styleSheets` (cross-origin `cssRules` access throws and reads as "absent").

- **Phlex blocks inline `on*` event handlers** (D11 — F1 role `<select>`). Rendering `select(onchange: "this.form.requestSubmit()")` — or any `onclick`/`oninput`/etc. — raises `Phlex::ArgumentError: Unsafe attribute name detected: onchange.` at render time (Phlex refuses the `UNSAFE_ATTRIBUTES` set as an XSS guard). Drive the behaviour from a **Stimulus controller** via `data-action` instead: `form_with(data: { controller: "auto-submit" })` + `select(data: { action: "change->auto-submit#submit" })`, with a controller whose `submit()` calls `this.element.requestSubmit()`. The new controller is stale in dev until `assets:precompile` + `bin/cli app restart` (importmap pin — same as the asset gotcha above). **A request spec can miss this** if the offending view branch never renders (D11's members index spec only had the admin's own *locked* row, so it never rendered the role `<select>` — the crash only surfaced in live `/product-review`); seed specs to hit **every** view branch and live-verify.

- **Provisioning live prod demo data:** `db/seeds.rb` is guarded off in production (`return if Rails.env.production?`). To stand up a demo org/account on prod, mirror the seed body in a one-off, idempotent `runner` script and pipe it in: `mise x -- kamal app exec -i --reuse 'bin/rails runner -' < /tmp/script.rb`. Scope it to a single new org slug + a verified (`status: 2`) account so passwordless login works; never touch the real org. (D10 set up `jlstaar@gmail.com` → `demo.move-easy.org` — agent memory `prod-demo-account`.)

---

## 5. Runtime Test Workflow (Mandatory)

After all code changes are committed and tests pass, perform a live runtime verification before pushing the branch or creating a PR (the `/product-review` skill automates this).

### Steps

1. **Rebuild the app:** `bin/cli app rebuild`
2. **Restart the app:** `bin/cli app restart`
3. **Start the mail service:** `bin/cli mail start`
4. **Verify email delivery** at `https://mail.move-easy.docker/` using `agent-browser`.
5. **Visually verify the app** at `https://move.move-easy.docker/` using `agent-browser`:
   - Home page renders correctly (logged out and logged in states).
   - Authentication flows work (create account, verify email, sign in, sign out — Rodauth, passwordless).
   - All CRUD pages render and function (e.g. Posts, Users — index, show, new, edit).
   - Account management pages render (show, edit).
   - Dark mode toggle works.
   - Flash messages (toasts) appear and dismiss.
   - Sidebar navigation links and active states are correct.
6. **Fix any runtime errors** found during live testing, commit the fix, and re-run the full test suite before pushing.

> **`agent-browser` + `data-turbo-confirm`:** a `button_to` carrying
> `data: { turbo_confirm: "…" }` fires a native `confirm()` dialog that
> `agent-browser` does **not** auto-accept, so the click looks like it did
> nothing (the form never submits — e.g. D10 "Mark box unpacked"). Patch it
> before clicking: `agent-browser eval "window.confirm = () => true"`, then click.
> (rack_test system specs ignore `turbo_confirm` and submit directly, so this only
> bites live browser verification.) Set a mobile viewport with
> `agent-browser set viewport 393 852` (not `resize`).

> **`agent-browser wait --load networkidle` hangs in dev.** The dev app keeps a
> long-lived connection open (rack-mini-profiler / Turbo), so "network idle" never
> fires and the wait burns the full 25s timeout after every `open`/`click`. Wait on
> something concrete instead — `wait <selector>`, `wait --text "…"`, or a fixed
> `wait 1500` — then `snapshot -i`. (Also: `screenshot --screenshot-dir` may not
> land where you expect; the bare `screenshot` prints the real saved path.)

### Runtime Verification Scripts

When verifying server-side logic via `bin/rails runner`, build fixtures with **FactoryBot factories** rather than raw `Model.create!`:

```ruby
post = FactoryBot.create(:post, user: user)
```

Raw `create!` silently misses required associations (e.g. `Post#user`), causing avoidable `RecordInvalid` failures and wasted rebuild/run cycles. Factories already encode every required association and a valid default state.

---

## 6. Skills

This repository ships agent skills under `.claude/skills/`. Prefer them for the workflows they cover:

- **`/execution-plan`** — drive a unit of work end-to-end (issue → branch → commits → live verify → PR → review response).
- **`/qa-remediation`** — turn review findings into tracked issues + atomic fix commits.
- **`/product-review`** — mandatory live product verification (this section's workflow).
- **`/security-review`** — adversarial, threat-model-driven pass over the branch
  diff. **Wired into `/execution-plan` as Step 5d** (run after `/code-review`, before
  push, on security-sensitive changes). Anchored to the rubric's "Security & data"
  section + [`doc/project/security-model.md`](doc/project/security-model.md). The
  whole-repo counterpart is the on-demand `Security Audit` workflow.
- **`/qa-review`**, **`/ux-review`**, **`/ui-polish`** — review passes before a PR is merged.
- **`/ui-designer`** — build Tailwind + Phlex UI from the component library.

## 7. Documentation after implementation (Mandatory)

Every change that touches **architecture, infrastructure, deployment, tenancy,
auth, or any cross-cutting flow** MUST update the project documentation **and its
diagrams** before the PR merges — code without docs is incomplete.

- **Where:** operational/architectural docs live in [`doc/project/`](doc/project)
  ([`README.md`](doc/project/README.md) index, [`architecture.md`](doc/project/architecture.md),
  [`new-app-recipe.md`](doc/project/new-app-recipe.md)). Product/phase docs stay in
  `doc/phases/`. Per-effort step logs (the flight recorder) stay in
  `doc/phases/<Phase> - Steps.md`.
- **Always include visual schemas**, not just prose:
  - **Mermaid** diagrams embedded in the markdown (render inline on GitHub) for
    request flows, schema/tenancy models, and sequence/lifecycle.
  - An **editable Excalidraw scene** in [`doc/project/diagrams/`](doc/project/diagrams)
    (`*.excalidraw`, openable at <https://excalidraw.com/>) for the headline
    architecture diagram. If an **Excalidraw MCP server** is connected, use it to
    author/regenerate the scene; otherwise hand-author the `.excalidraw` JSON.
- **Keep the recipe reproducible:** when you add/alter a setup step (a gem, a
  Kamal/Cloudflare/Doppler/CI setting, an install command), update
  `new-app-recipe.md` with the exact command/config so the next app is a copy-paste.
- **Keep the design system in sync — [`DESIGN.md`](DESIGN.md).** Any change that
  adds or alters a **design token** (`app/assets/tailwind/application.css` — the
  `@theme` block or the `--c-*` light/dark runtime palette) **or** the **`Ui::*`
  Phlex component library** (`app/components/ui/` — a new component, or a new
  variant/state on an existing one) MUST update `DESIGN.md` in the **same PR**.
  `DESIGN.md` is a hand-maintained mirror, so it drifts the moment a token/component
  ships undocumented; `application.css` stays authoritative (the doc says so) and
  `DESIGN.md` is the consolidated human reference. **`/code-review` flags a
  token/`Ui::*` change whose diff doesn't also touch `DESIGN.md`.**
- **Record hard-won gotchas** in the recipe's gotcha table and in agent memory.
- Reference these docs from the PR description.

## 8. Seed data after implementation (Mandatory)

Every phase that adds a user-facing surface MUST extend
[`db/seeds.rb`](db/seeds.rb) so that, after `bin/rails db:seed`, a developer can
sign in and **immediately showcase and play with** the new feature — no manual
record-building. The seed data is part of the deliverable, not an afterthought.

- **Comprehensive states.** Seed records across the meaningful states the surface
  can render (e.g. for Boxes: sealed/packing/in-transit, with and without
  dimensions, multiple rooms, an empty case). Reviewers and the `/product-review`
  pass rely on this coverage.
- **Idempotent.** Use `find_or_create_by`/`find_or_initialize_by` keyed on a
  natural attribute so re-running `db:seed` never duplicates.
- **Never seed production.** Keep the `return if Rails.env.production?` guard —
  `db:prepare` auto-runs seeds on a fresh DB and demo accounts/tenants must not
  reach the live registry (this leaked before).
- **Tenancy-aware.** Provision the demo tenant via `Organizations::Create`, then
  `Apartment::Tenant.switch` to seed Move-scoped records. Guard the demo to the
  base schema (`return unless Apartment::Tenant.current == "public"`) — Apartment
  re-runs `db:seed` per tenant.
- **Loginable account.** Seeded sign-in accounts need `status: 2` (verified) to
  use the passwordless email link. Document the demo email + org subdomain in a
  comment at the top of `db/seeds.rb`.
- **Verify.** Run `bin/rails db:seed` twice (idempotency) and confirm the new
  records render during `/product-review`.

## Skill Self-Evaluation

After using any skill from this project, append a brief retrospective:

**Skill used**: [skill name]
**Step audit**:
- Any step that was redundant or unnecessary → note it
- Any step whose output was unused → note it
- Any command that produced an error or required a workaround → note it
- Any step where you deviated from the skill's instructions → explain why

**Improvement suggestion**: One concrete, actionable edit to the SKILL.md that would fix the most significant issue found. If none, write "No changes suggested."

<!-- code-graph-mcp:begin v2 -->
## Code Graph (repo-wide AST index)

AST + FTS + vector index of the whole repo — prefer over multi-round Grep/Read for
structural queries (LSP only sees open files; this sees everything). Fastest path = Bash CLI:

| Intent | Command |
|--------|---------|
| Who calls X / what X calls | `code-graph-mcp callgraph X` |
| Impact before editing a fn | `code-graph-mcp impact X` |
| Unfamiliar dir / module | `code-graph-mcp overview <dir>` |
| Symbol source / signature | `code-graph-mcp show X` |
| Concept search (no exact name) | `code-graph-mcp search "…"` (vector: MCP `semantic_code_search`) |
| grep + AST context | `code-graph-mcp grep "pat" [paths] [-t lang] [-g glob] [-c]` |

Still use Grep for literal strings/regex in non-code files; still Read files you'll edit.
Full command + MCP-tool table: `.claude/plugin_code_graph_mcp.md`
<!-- code-graph-mcp:end -->
