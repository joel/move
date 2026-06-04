# AGENTS.md

This document provides instructions and protocols for AI Agents interacting with this repository. **Follow these guidelines strictly to ensure project consistency.**

## 1. Context & Environment

- **Live Testing:** Use the `agent-browser` tool (and the `/product-review` skill) to verify changes visually and functionally.

- **GitHub CLI:** Always `unset GITHUB_TOKEN` before running `gh` commands. The environment may have a stale token that causes `HTTP 401: Bad credentials` errors. The `gh` CLI falls back to its own auth store when the env var is unset.

- **Ruby version manager:** This project uses **mise**. Prefix Ruby/Rails commands with `mise x --` (e.g. `mise x -- bundle exec rspec`) so the project's Ruby (`.ruby-version`) is used.

- **URLs:** Local development (via `bin/cli`): `https://move.workeverywhere.docker` (mail at `https://mail.workeverywhere.docker`). Production: `https://move.workeverywhere.app`.

### Design source of truth (Google Stitch)

**The visual design lives in Google Stitch, reached through the Stitch MCP server — not in the codebase or your imagination.** Before building or changing any **customer-facing** screen, you MUST open the real design and build against it. Never guess a layout, colour, spacing, radius, or type value.

- **Project:** `Move Design` → `projects/13869765800416404511` (a separate `Move Inventory Manager` project also exists — do not confuse them).
- **Design system (tokens):** `mcp__stitch__get_project name=projects/13869765800416404511` → `designTheme.designMd`. This is the authoritative colour/typography/spacing/radius/component sheet. It is mirrored in `doc/phases/Phase D0 - Design Foundation.md`.
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

- **Pre-commit:** trailing whitespace, `FIXME` tokens, **RuboCop**, **ErbLint**, **BundleCheck**, **LocalPathsInGemfile**, and **RailsSchemaUpToDate** (the committed `db/schema.rb` must match the migrations).

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
5. Run the **Pre-Commit Validation** (lint + tests) and make atomic commits.
6. Perform live verification (see **Runtime Test Workflow** / `/product-review`).
7. Push the branch and open a PR with a summary and test plan (`Closes #<issue>`). Wait for the required `lint` and `test` checks.
8. Respond to **every** review comment and resolve each conversation (see below).
9. After the PR is merged to `main` (squash), the **production deploy runs automatically** (see **Deployment**).
10. Tag a release when the change warrants one (see **Release Rules**).

### PR Review Response Rules

When a PR receives code review comments:

1. **Read all comments** using `gh api repos/joel/move/pulls/<PR>/comments`.
2. **Evaluate each comment** — decide whether to act on it, explain why not, or defer to a follow-up issue.
3. **For actionable feedback:** Fix the code, commit, push, then reply explaining what was fixed and in which commit.
4. **For incorrect feedback:** Reply with a clear technical explanation of why no action is needed.
5. **For deferred feedback:** Reply acknowledging the concern and stating which follow-up issue/PR will address it.
6. **Reply to every comment** using `gh api repos/joel/move/pulls/<PR>/comments/<ID>/replies -X POST -f body='...'`. The `<PR>` number is required — omitting it (`gh api repos/joel/move/pulls/comments/<ID>/replies`) returns `HTTP 404: Not Found`.
7. **Resolve every conversation** after replying using the GraphQL `resolveReviewThread` mutation.
8. Never leave review comments unanswered or unresolved.

### Deployment

- `.github/workflows/deploy.yml` deploys to production (`move.workeverywhere.app`) via **Kamal** on **every push to `main`** (i.e. every merge).
- Secrets come from **Doppler** (`move/prd`), synced into GitHub Actions secrets. `.kamal/secrets` uses the environment-provided values in CI and falls back to the Doppler CLI / `config/master.key` for local deploys.
- Skip a deploy for a given commit with `[skip deploy]` in the commit **subject**. **Beware:** a squash-merge whose body quotes the literal `[skip deploy]` (for example, by referencing this document) will skip the deploy unintentionally.

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

- **Do not use `[skip ci]` markers.** CI decides whether to run via `paths-ignore` in `.github/workflows/ci.yml` (`**/*.md`, `.claude/**` are ignored automatically). If a new path should be exempt from CI, add it to `paths-ignore` instead of relying on commit-message markers.

- **Test full user journeys, not just page rendering.** Runtime tests must verify multi-step flows end-to-end (e.g. sign up → verify email → sign in → perform an action → see the result). A page rendering correctly does not guarantee the logic behind it works. If a feature involves events, subscribers, or background jobs, verify the downstream effects actually happen (check emails in the local mail service, check database records).

- **Rails 8.1 `Rails.event` structured events.** Subscribers must respond to `#emit(event)`, not `#call`. The event is a hash: `event[:name]`, `event[:payload]`, `event[:tags]`, etc. Register with `Rails.event.subscribe(subscriber)` and an optional filter block: `{ |e| e[:name].start_with?("prefix.") }`.

- **Shell escaping with `docker exec` + `bin/rails runner`.** Ruby bang methods (`save!`, `find_by!`) break in shell because `!` is interpreted by bash. Use a heredoc redirect instead: `docker exec -i <container> bin/rails runner - < /tmp/script.rb`.

- **Rodauth forms lose query parameters on POST.** If a URL carries query params (e.g. `?token=xxx`), the Rodauth form POST will not include them. Add hidden fields in the Phlex view to carry params through.

- **Pre-fill forms from context, not just params.** When a URL carries context (tokens, IDs) that determines valid input, pre-fill and lock the relevant fields. Never rely on the user to type something the system already knows — mismatches cause silent rejections that look like bugs.

---

## 5. Runtime Test Workflow (Mandatory)

After all code changes are committed and tests pass, perform a live runtime verification before pushing the branch or creating a PR (the `/product-review` skill automates this).

### Steps

1. **Rebuild the app:** `bin/cli app rebuild`
2. **Restart the app:** `bin/cli app restart`
3. **Start the mail service:** `bin/cli mail start`
4. **Verify email delivery** at `https://mail.workeverywhere.docker/` using `agent-browser`.
5. **Visually verify the app** at `https://move.workeverywhere.docker/` using `agent-browser`:
   - Home page renders correctly (logged out and logged in states).
   - Authentication flows work (create account, verify email, sign in, sign out — Rodauth, passwordless).
   - All CRUD pages render and function (e.g. Posts, Users — index, show, new, edit).
   - Account management pages render (show, edit).
   - Dark mode toggle works.
   - Flash messages (toasts) appear and dismiss.
   - Sidebar navigation links and active states are correct.
6. **Fix any runtime errors** found during live testing, commit the fix, and re-run the full test suite before pushing.

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
- **`/qa-review`**, **`/security-review`**, **`/ux-review`**, **`/ui-polish`** — review passes before a PR is merged.
- **`/ui-designer`** — build Tailwind + Phlex UI from the component library.

## Skill Self-Evaluation

After using any skill from this project, append a brief retrospective:

**Skill used**: [skill name]
**Step audit**:
- Any step that was redundant or unnecessary → note it
- Any step whose output was unused → note it
- Any command that produced an error or required a workaround → note it
- Any step where you deviated from the skill's instructions → explain why

**Improvement suggestion**: One concrete, actionable edit to the SKILL.md that would fix the most significant issue found. If none, write "No changes suggested."
