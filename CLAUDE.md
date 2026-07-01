# AGENTS.md

This document provides instructions and protocols for AI Agents interacting with this repository. **Follow these guidelines strictly to ensure project consistency.**

## 1. Context & Environment

- **Live Testing:** Use the `agent-browser` tool (and the `/product-review` skill) to verify changes visually and functionally.

- **GitHub CLI:** Always `unset GITHUB_TOKEN` before running `gh` commands. The environment may have a stale token that causes `HTTP 401: Bad credentials` errors. The `gh` CLI falls back to its own auth store when the env var is unset.

- **Ruby version manager:** This project uses **mise**. Prefix Ruby/Rails commands with `mise x --` (e.g. `mise x -- bundle exec rspec`) so the project's Ruby (`.ruby-version`) is used.

- **URLs:** Local development (via `bin/cli`): `https://move.move-easy.docker` (mail at `https://mail.move-easy.docker`). Production: `https://move-easy.org` (apex/login; org subdomains `<slug>.move-easy.org`), behind Cloudflare (Full Strict, Origin CA wildcard cert served by kamal-proxy).

### Foundational Architecture & Design Standards

Read the memory anchors below before implementing any feature or major refactor. These are non-negotiable patterns, enforced by cops, tests, and review:

- **[[design-source-of-truth]]** — Google Stitch is authoritative for customer-facing UI; fetch the real design before building.
- **[[ux-interaction-conventions]]** — Four rules: visible results, useful order, hide zero-value, remember context.
- **[[architecture-engineering-conventions]]** — Six rules: Apartment tenancy, action-based logic, live auth testing, ActionCable for live updates, database aggregation, Packwerk boundaries.
- **[[deployment-and-release-rules]]** — Kamal deployment, PG18 accessory management, SemVer release, squash-merge hygiene.

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

### Deployment & Release

Read **[[deployment-and-release-rules]]** for the full runbook:
- Kamal deployment on every `main` push
- Doppler secrets management
- Skip-deploy markers and gotchas
- PG18 accessory cutover procedures
- SemVer release workflow

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

## 7. Documentation & Seed Data (Mandatory)

Read **[[documentation-and-seed-mandate]]** for the full requirements:
- Every architecture/infrastructure/auth change must update docs + diagrams before merge
- Keep [`DESIGN.md`](DESIGN.md) in sync with design tokens and `Ui::*` components (`/code-review` flags mismatches)
- Every user-facing feature must extend [`db/seeds.rb`](db/seeds.rb) with comprehensive test data

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
