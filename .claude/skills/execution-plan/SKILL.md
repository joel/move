---
name: execution-plan
description: Drive the end-to-end execution of any coherent piece of code work in this project — from a design pass (codebase exploration and architecture via the feature-dev agents, plus the frontend-design skill for visual/UI direction), through issue creation, branching, implementation, testing, live verification, PR, and review response. Trigger whenever the user asks to implement a feature, fix a bug, refactor code, ship a change, or act on a plan that will produce commits. Also trigger when they say "start work", "new feature", "fix issue", "create PR", "push changes", "let's implement", "execute the plan", or reference a planning document that needs to be carried out. Keeps the loop intact — design pass first, then GitHub issue, then Kanban move, then branch, then atomic commits, then live product verification, then PR, then review response — none of the steps silently drop.
---

# Execution Plan

This skill enforces the full development workflow defined in the project's development-workflow doc (e.g. AGENTS.md / CLAUDE.md). Every coherent piece of code work follows this lifecycle: Issue → Kanban → Branch → Implement → Test → Live Verify → Push → PR → Review → Respond → Resolve.

## Why This Matters

Skipping steps (especially GitHub issues, Kanban updates, and live testing) creates tracking gaps and lets runtime bugs slip through. The automated test suite catches logic errors but not rendering issues, broken layouts, or Phlex/ERB integration problems. Live verification regularly catches runtime errors (e.g. a `Phlex::ArgumentError`) that unit and system tests miss.

## GitHub CLI Authentication

The `GITHUB_TOKEN` environment variable can override keyring-based authentication and cause failures. Always prefix `gh` commands with `unset GITHUB_TOKEN &&`:

```bash
gh issue create ...
gh pr create ...
gh project item-add ...
```

## Project References

- **Repository:** `<owner>/<repo>` (`https://github.com/<owner>/<repo>`)
- **Issues:** `https://github.com/<owner>/<repo>/issues`
- **Kanban Board:** `https://github.com/users/<owner>/projects/<project-number>/views/1` (Project number: `<project-number>`)
- **Available Labels:** `bug`, `enhancement`, `cleanup`, `documentation`, `dependencies`, `ruby`

### Kanban Status IDs

The board uses a single-select status field. An example set of statuses:

| Status      | Option ID     |
|-------------|---------------|
| Backlog     | `<option-id>` |
| Ready       | `<option-id>` |
| In progress | `<option-id>` |
| In review   | `<option-id>` |
| Done        | `<option-id>` |

**Status field ID:** `<status-field-id>`

The project ID, status field ID, and the per-status option IDs are project-specific. Retrieve them for your project with:

```bash
gh project field-list <project-number> --owner <owner> --format json
```

## Audit Trail (Optional)

If your project keeps a running steps/audit log per effort (e.g. a per-effort `Steps.md` next to its plan), maintain it here.

**Why it exists.** Git and GitHub record *what* happened; an audit log records *why* and *in what order*, readable sequentially by a human without clicking through commit bodies and issue threads. It's a flight recorder — useful when picking up work after a context reset or when explaining to a reviewer how the work unfolded.

**How to maintain it.** Append-only. Create it alongside the GitHub issue (Step 1) and update at these points:

| At step | Append |
|---------|--------|
| 1 (issue) | issue number, title, link to the plan, "User approved the plan." |
| 4 (branch) | branch name |
| 7 (commit) | `<sha>` + one-line rationale; note any `SKIP=<hook>` with reason |
| 8 (runtime test) | pages verified, anything that broke and the fix commit |
| 11 (PR review round) | per-comment action + fix commit + resolution, as a table |
| 13 (release) | CHANGELOG entry filled, then release tag + release URL, if the project versions releases |
| 12/14 (done) | final summary table: issue → commit → release → status |
| 15 (persist) | memories written/updated, docs touched, follow-up issues filed |

**Tone.** Factual, short. The audience is future-you (or a reviewer) reconstructing what decisions were made, not re-arguing them.

## Design Phase (delegated to the `feature-dev` plugin)

The *understand-and-design* inner loop (and the pre-push review) are owned by
Anthropic's official plugins, not duplicated here. The `feature-dev` subagents are
registered in this session and invoked by `subagent_type` via the Agent tool;
`frontend-design` and `/code-review` are skills invoked via the Skill tool — there is
nothing to copy:

| Capability | Kind | Use it to |
|---|---|---|
| `feature-dev:code-explorer` | agent (`subagent_type`) | Trace how the relevant area works before you plan (P2) |
| `feature-dev:code-architect` | agent (`subagent_type`) | Get an implementation blueprint grounded in real patterns (P4) |
| `frontend-design` | skill (Skill tool) | Visual/UI direction — palette, type, layout, signature — for customer-facing surfaces |
| `/code-review` | skill (Skill tool) | The pre-push **Code Review (CR) loop** — see Step 5c. Our own review before the PR exists, so it front-runs (and shortens) the remote Codex loop |

The plugins stay the upstream source of truth — when Anthropic updates them, this
skill inherits the change for free. The skill keeps only the project-specific
governance and gates below.

### Scale the design pass to the task size

Run the design agents in proportion to the work — don't over-process a one-liner
(this mirrors feature-dev's own "Don't use for trivial changes"):

- **Trivial** (one-line fix, copy/docs change, dependency bump, config tweak): **skip
  the design agents.** Go straight to the issue → branch → commit governance steps.
- **Feature / multi-file / architectural** (touches multiple files, adds a surface,
  or needs a design decision): **run the full design pass before writing the issue**,
  so the issue's plan (Step 1) is grounded in real code, not guesses:
  1. Launch **2–3 `feature-dev:code-explorer`** agents in parallel, each targeting a
     different aspect (similar features, architecture/abstractions, UX/extension
     points). Read the key files each returns.
  2. Resolve ambiguities (feature-dev P3) — ask the user concrete clarifying
     questions and wait for answers before designing.
  3. **For customer-facing UI work**, invoke the **`frontend-design`** skill for the
     visual pass — palette, typography, layout, and the signature element — so the
     surface reads as a deliberate design, not a templated default.

     > **`frontend-design` leads the visual direction; Stitch is secondary.** Drive
     > the look from the `frontend-design` pass — make the deliberate, opinionated
     > palette/type/layout choices it calls for. Treat the Google Stitch screens (via
     > the Stitch MCP) as a **reference input** — existing tokens, prior art, and
     > consistency cues to fold in — not as a constraint that overrides the design
     > pass. When the two diverge, the `frontend-design` direction wins. After
     > settling the design, **push the result back into Stitch** (update or generate
     > the screen, record the `screens/<id>` per `CLAUDE.md`) so Stitch stays in sync
     > with what shipped.
     >
     > **Note:** this deliberately **overrides** `CLAUDE.md`'s "Stitch is the design
     > source of truth / never invent visual values" rule for the design pass — by
     > explicit instruction. Keep the project's design *tokens* (Phase D0) and Phlex
     > component library as the build substrate regardless.
  4. **For any user-facing change (not just visual), do an interaction/UX pass**
     against `doc/project/ux-conventions.md` — the behavioural counterpart to the
     Phase D0 visual system. `frontend-design` (step 3) covers how it *looks*; this
     covers how it *behaves*. Walk that doc's planning checklist for **every user
     journey** the change touches and decide, explicitly:
     - **Default ordering** — the most *useful* order for the task (recency / weight /
       count / priority), not insertion order or alphabetical.
     - **After each action** — where the user lands, that the new/changed item is
       visible without scrolling (scroll-to / highlight / top-insert + a linking
       toast), and where focus goes.
     - **Every state** — empty / sparse / loading / processing / error; and hide any
       element that is useless in a given state (e.g. zero-count facets, tags with no
       records).
     - **Memory** — whether the surface should remember the user's last useful
       input/result instead of resetting to a placeholder.

     These are **requirements the architect blueprint must encode**, not
     afterthoughts — the class of papercut (new record hidden off-screen, useless
     alphabetical sort, dead facets, forgetful search) comes from deciding them ad
     hoc per surface. New rules discovered here get added to `ux-conventions.md` and
     mirrored into `AGENTS.md` so the `/code-review` CR loop (Step 5c) enforces them;
     there is **no official UX-review plugin**, so UI-heavy changes also warrant a
     focused UX-critic agent run (`ux-conventions.md` as the rubric).
  5. Launch **2–3 `feature-dev:code-architect`** agents in parallel (minimal-change,
     clean-architecture, pragmatic-balance). Pick one, with reasoning; confirm the
     approach with the user.
  6. Feed the chosen blueprint (UI **and** UX decisions) into the issue plan (Step 1)
     and the implementation (Step 5).

> The full interactive `/feature-dev` *command* is a separate top-level flow that is
> blind to this project's governance (issues, Kanban, Codex, releases). Do **not**
> drive an execution-plan run through it — invoke the **agents** above instead. Use
> the bare `/feature-dev` command only for standalone design exploration outside this
> lifecycle.

## Workflow Steps

### Step 1: Create GitHub Issue

Before writing any code, create an issue with a detailed plan. For feature/multi-file
work, base the **Summary/Scope** on the `code-explorer` findings and the chosen
`code-architect` blueprint from the Design Phase — the issue plan should reflect real
code, not assumptions.

```bash
gh issue create \
  --repo <owner>/<repo> \
  --title "<descriptive title>" \
  --label "<label>" \
  --body "$(cat <<'EOF'
## Summary
<what and why>

## Scope
<bullet list of changes>

## Verification
<how to confirm it works>
EOF
)"
```

Pick the label that best fits: `enhancement` for features, `bug` for fixes, `cleanup` for refactoring, `documentation` for docs.

### Step 2: Add to Kanban Board → Backlog

```bash
gh project item-add <project-number> --owner <owner> --url <issue-url>
```

The issue starts in **Backlog** by default. Save the item ID from the output (or retrieve it later with `gh project item-list`).

### Step 3: Move to Ready, Then In Progress

To move an issue on the board, you need its **item ID**. Retrieve it:

```bash
gh project item-list <project-number> --owner <owner> --format json \
  | jq -r '.items[] | select(.content.number == <ISSUE_NUMBER>) | .id'
```

Then update the status (option IDs from `gh project field-list`, see Project References):

```bash
# Move to Ready (before starting work)
gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <ready-option-id>

# Move to In Progress (when starting work)
gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <in-progress-option-id>
```

### Step 4: Create Feature Branch

```bash
git checkout main && git pull origin main
git checkout -b feature/<descriptive-name>
```

Branch naming: `feature/*` for features, `fix/*` for bugs, `docs/*` for documentation, `refactor/*` for refactoring.

### Step 5: Implement Changes

Implement the `feature-dev:code-architect` blueprint from the Design Phase (for
trivial changes, just implement directly), following project conventions. If your Ruby
version manager needs activation (rv/mise/etc.), prefix Ruby commands accordingly.

**Live updates → ActionCable, never JS polling.** To reflect server-side progress or state in the UI, push it over ActionCable / turbo-rails Turbo Stream broadcasting — `setInterval`+`fetch`, Stimulus pollers, and refresh meta tags are **forbidden**. See `AGENTS.md` §1 convention #4 (signed stream from a tenant-unique record; subscriber re-renders via `ApplicationController.render(view, layout: false)` + `Turbo::StreamsChannel.broadcast_replace_to`; wrap the broadcast in a `rescue` so it can't fail the emitting action). Reference impls: #239 (indexing progress), #241 (capture panel).

### Step 5b: Seed data (Mandatory for any new user-facing surface)

Extend `db/seeds.rb` so that after `bin/reset` a developer can sign in and **immediately showcase and play with** the surface this phase adds — no manual record-building. See the project's `AGENTS.md` §8 for the full rule. In short:

- **Comprehensive states** — seed records across the meaningful states the surface renders (lifecycle states, with/without optional data, an empty case).
- **Idempotent** — `find_or_create_by` keyed on a natural attribute; re-running never duplicates.
- **Production-guarded** — keep `return if Rails.env.production?` (`db:prepare` auto-seeds a fresh DB).
- **Tenancy-aware** — provision the demo tenant via the tenant-creation action, `Apartment::Tenant.switch` for tenant-scoped records, and guard the demo to the base schema (`return unless Apartment::Tenant.current == "public"`).
- **Loginable** — seeded sign-in accounts need a verified status; note the demo email + org subdomain in a comment.
- **Verify** — run `bin/rails db:seed` twice **against the same database** (idempotency: `bin/reset` drops/recreates the DB, so re-running it can't catch non-idempotent seeds — it masks them), and confirm the records render during Step 8 (`/product-review`).

### Step 5c: Code Review (CR) — internal review loop before push

**Goal: review our own code *before* the PR exists, so the remote Codex loop
(Step 10b) opens on already-clean code instead of becoming the first reviewer.**
Most Codex round-trips are findings we could have caught locally; this phase exists
specifically to absorb them in a cheap local loop and keep the expensive
PR → CI → Codex loop short. Skip only for trivial changes.

Use the official Anthropic **`/code-review`** skill on your working-tree diff (it
runs confidence-scored, multi-agent passes over the current diff, reads
`CLAUDE.md`/`AGENTS.md`, and surfaces only high-confidence issues):

```
/code-review            # scale effort to the change — default for most work
/code-review high       # high→max for security / auth / concurrency / wide blast radius
```

**The loop:**

1. **Run `/code-review`** (optionally `--fix` to apply mechanical fixes to the working
   tree; `--comment` is for PR mode — not used here, pre-push).
2. **Triage each finding exactly like a Codex comment (Step 11b):** fix the real ones
   (fold into the relevant atomic commit); for a suspected false positive,
   reproduce-before-dismissing; defer to a tracked issue only when genuinely justified.
3. **Re-run** after the fixes and repeat **until a round comes back clean** (or the only
   remainder is explicitly deferred).

> **Round until satisfied — but heed the SAME stop rule as Step 10b:
> "Know when to stop — findings have diminishing returns on mature code."** Read that
> section; it governs this loop too. The CR loop converges in *severity*: early rounds
> catch real bugs (correctness, ordering, security), later rounds shrink to contrived
> nitpicks on already-correct code. So:
> - When findings degrade to cosmetic nits, or each needs a more elaborate/unlikely
>   condition to trigger, **stop and push** — don't spend a full extra cycle on a nit.
> - Prefer **one principled fix** (a small invariant/state machine) over patching each
>   adjacent edge case; one correct model ends the whack-a-mole.
> - "Clean" on living code isn't guaranteed on any finite round — **two substantive
>   rounds that converge is enough.** The aim is to ship correct code, not to chase a
>   perfect verdict locally any more than remotely.

Catching findings here turns later Codex rounds into confirmations rather than rework —
that is the whole point of the phase.

### Step 6: Pre-Commit Validation

Run the project's lint/test/system-test tasks and ensure they all pass before committing. Many Rails projects expose these as rake tasks; run everything at once with:

```bash
bundle exec rake
```

If the project splits them out (e.g. fix-lint, lint, tests, system-tests tasks), run each in turn. Confirm the task names against the project's Rakefile rather than assuming they exist.

> **`:js`/system specs needing a real browser CANNOT be validated in the dev app
> container — chromedriver is absent there.** Such specs run in real Chrome even
> under `TEST_BROWSER=rack_test` (see agent memory), so in the dev container they
> fail with `Selenium::WebDriver::Error::WebDriverError: ... 127.0.0.1:9515:
> Connection refused`. **Treat that error as environmental (CI-only), not a code
> regression** — don't burn cycles "fixing" it locally. Run the non-`:js` system
> specs locally (they pass under `rack_test`), and rely on the CI `test` job (which
> provisions Chrome) for the `:js` ones. Confirm CI green on HEAD before merge
> (Step 10b). If a `:js`-covered surface is central to the change, live-verify it
> instead via `/product-review` (real browser through `agent-browser`).

### Step 7: Commit (Atomic Commits Required)

**NEVER bundle all changes into a single giant commit.** Each commit must be:

- **Atomic:** One logical change per commit (e.g., "harden pagination", "fix policy bypass", "add comment edit UI" are three separate commits, not one)
- **Focused:** Only files related to that one change are included
- **Reversible:** Any commit can be reverted independently without breaking other changes
- **Buildable:** Each commit passes lint and tests on its own

When implementing a multi-part feature, commit after each logical unit is complete and green. Run the project's lint + test tasks before each commit.

Stage specific files (not `git add .`) and use a descriptive commit message. Overcommit hooks will enforce RuboCop, trailing whitespace, and commit message format (capitalized subject, no trailing period).

> **Verify the commit actually contains every file you changed.** Staging an
> explicit file list is safer than `git add .`, but it's also how an edited file
> gets silently left behind — you commit, the build still passes (the working
> tree has your fix), and the *old* version ships. After committing, confirm with
> `git show --stat HEAD` (or `git status` is clean of intended changes). This bit
> hard once: a scanner security fix was edited but never staged, so the unsafe
> version merged and a correct Codex re-flag looked like a false positive. If a
> review says "you didn't fix X" and you're sure you did, check the **pushed**
> code (`git show origin/<branch>:<path>`), not your working tree.

If a hook is a false positive, skip only that specific hook and document it:

```bash
SKIP=RailsSchemaUpToDate git commit -m "$(cat <<'EOF'
Your commit message here

Skipped RailsSchemaUpToDate: schema unchanged, migration is no-op

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

Never use `OVERCOMMIT_DISABLE=1`.

> **A subject-only commit starting with `#<issue>` can fail the `EmptyMessage`
> hook.** Git's default `commentChar` is `#`, so a message that is a single
> `#…` line with no body gets stripped to nothing and the hook rejects it
> (`Commit message should not be empty`). The multi-line `-m "$(cat <<'EOF' … EOF)"`
> commits in this skill are unaffected (they have a body); it only bites a quick
> `git commit -m "#91 Link PR"`. Fix: add a body, or use
> `git -c core.commentChar=";" commit -m "#91 …"`.

**`[skip ci]` flag (⚠ project override):** the generic advice is to add `[skip ci]`
to docs-only/comment-only commits. **In the `move` repo, do NOT** — a squash-merge
folds commit bodies into the merge commit, and any `[skip ci]`/`[skip deploy]`
marker there silently skips the **production deploy**. CI already path-ignores
`**/*.md`, `doc/**`, `.claude/**` via `paths-ignore`, so docs commits need no
marker. (See `AGENTS.md` §4 Deployment.)

### Step 8: Runtime Test Workflow

After committing and before pushing, perform live verification. Use the
`/product-review` skill for the full checklist when it is available.

> **Fallback when `/product-review` is not invocable.** In some sessions the
> `product-review` skill is **not registered** under that name (the Skill tool
> rejects it as unknown). When that happens, do **not** skip live verification —
> drive it directly instead:
> - the **`/verify`** skill (runs the app and observes behaviour), or
> - the manual loop below: `agent-browser` for rendering/interaction, and
>   `bin/rails runner` (via `docker exec -i move-app-dev bin/rails runner -`) for
>   server-side setup (mint magic links / tokens — dev mail is unreachable from the
>   container; see agent memory `dev-magic-link-mint`).

```bash
bin/cli app rebuild
bin/cli app restart
bin/cli mail start
```

Then use `agent-browser` to verify all pages render without errors. Fix any issues found, commit the fix, and re-run the test suite.

> **Auth / cookie / session changes — verify the wire, not just the screen.** A
> browser snapshot shows a page rendered, but cookie **scope** and **isolation** are
> invisible in it. For changes to cookie domains, session/remember handling, or
> cross-host/tenant auth (e.g. host-only cookies, an apex↔subdomain handoff),
> inspect the **raw `Set-Cookie` headers** with `curl` and a cookie jar — it proves
> the security property far more rigorously than a visual review:
 ```bash
> # Capture cookies. Netscape jar fields (TAB-separated):
> #   1=domain  2=include_subdomains(TRUE/FALSE)  3=path  4=secure  5=expiry  6=name  7=value
> curl -sk -c jar.txt -o /dev/null -w "%{http_code} %{redirect_url}\n" "<url>"
> grep -E "_session|_remember" jar.txt | awk -F'\t' '{print $6": domain="$1" include_subdomains="$2}'
> ```
> **Host-only is field 2 == `FALSE`, NOT the domain string.** Host-only means the
> `Domain` attribute is *omitted*; an explicit `Domain=<current-host>` (even when it
> equals the request host) still records `include_subdomains=TRUE` and is therefore
> **not** host-only — it would also be sent to deeper subdomains. So checking `$1`
> alone (the domain) can falsely pass; assert `$2` is `FALSE` for every auth cookie.
> ```bash
> # Isolation: a cookie set on host A must NOT authenticate host B.
> curl -sk -b jar.txt -o /dev/null -w "%{http_code}\n" "<other-host>/<authed-path>"  # expect 401
> # Single-use / expiry: replay the same token/URL → expect rejection.
> ```
> Assert the four things specs can't easily see: every auth cookie is host-only
> (jar field 2 == `FALSE`); the cookie does **not** authenticate a different host;
> single-use tokens reject on replay; and expired/garbage tokens land on the
> failure page.

### Step 8b: Update documentation + diagrams (Mandatory for cross-cutting work)

If the change touches **architecture, infrastructure, deployment, tenancy, auth, or
any cross-cutting flow**, update the project docs **and their visual schemas**
before pushing (see the project's `AGENTS.md` §7):

- Update `doc/project/` — `architecture.md`, `new-app-recipe.md` (keep setup
  commands/config copy-paste reproducible), and the gotcha table. Append to the
  per-effort `doc/phases/<Phase> - Steps.md` flight recorder.
- Include **visual schemas**, not just prose: **Mermaid** diagrams inline in the
  markdown (request flows, schema/tenancy, sequence/lifecycle), and an **editable
  Excalidraw scene** in `doc/project/diagrams/*.excalidraw` for the headline
  architecture. If an **Excalidraw MCP server** is connected, use it to
  author/regenerate the scene; otherwise hand-author the `.excalidraw` JSON.
- Commit docs atomically (markdown-only commits are path-ignored by CI). Record
  hard-won gotchas in agent memory too.
- In specific directory like: `app/actions/README.md` or `app/views/README.md`, add a **per-directory README** with a short
  summary of the directory's purpose, its key files, and any gotchas. This is
  especially important for directories that are not obvious from their name.

**Design-system sync (so `DESIGN.md` never drifts).** Independently of the
"cross-cutting" trigger above, if this change adds or alters a **design token**
(`app/assets/tailwind/application.css` — the `@theme` block or the `--c-*`
light/dark runtime palette) **or** the **`Ui::*` Phlex component library**
(`app/components/ui/` — a new component, or a new variant/state on an existing
one), update the root **`DESIGN.md`** in the **same PR** (project `AGENTS.md` §7).
`application.css` stays authoritative; `DESIGN.md` is the consolidated human
mirror, so it goes stale the moment a token/component ships undocumented. The
`/code-review` CR loop (Step 5c) flags a token/`Ui::*` diff that doesn't also
touch `DESIGN.md`. Read `DESIGN.md` during the Design Phase too — it is the quick
in-repo reference for the visual system (palette/type/spacing/components) that the
`frontend-design` pass builds on.

> **Don't leave a docs-only commit as the PR tip.** Branch protection requires the
> `lint`/`test` checks **on the HEAD sha**, but CI path-ignores `**/*.md`/`doc/**`/
> `.claude/**` — so a docs-only HEAD never runs CI and the PR stays
> `mergeStateStatus: BLOCKED`. Order commits so **code lands last**, or fold a
> trailing docs commit into the preceding code commit before pushing
> (`git reset --soft <code-sha>` → re-stage docs → `git commit --amend` →
> `git push --force-with-lease`; confirm the net tree is unchanged with
> `git diff <backup-branch> HEAD`). A *fully* docs-only PR is the same problem —
> those get admin-merged.

### Step 9: Push and Create PR

```bash
git push -u origin <branch-name>
```

Create the PR with a summary and test plan:

```bash
gh pr create \
  --repo <owner>/<repo> \
  --title "<PR title>" \
  --body "$(cat <<'EOF'
## Summary
<bullet points of what changed>

## Test plan
- [x] All non-system specs pass
- [x] All system specs pass
- [x] Lint passes
- [x] All overcommit hooks pass
- [x] Visual verification at https://<app-host>

Closes #<issue-number>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 10: Move Issue to In Review

```bash
gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <in-review-option-id>
```

### Step 10b: Wait for and check the Codex automated review (DO NOT SKIP)

This repo has **Codex** (`chatgpt-codex-connector[bot]`) configured to review every
PR automatically — it posts a review **a few minutes after the PR is opened** (or
is re-triggered by pushing new commits / commenting `@codex review`).

**Proactively wait for and check the Codex review before declaring the work done
or handing back to the user — without being asked.** Opening the PR is not the end
of the loop; the Codex pass is part of it. The user should never have to say
"check Codex's comment".

```bash
# Poll until Codex has reviewed (its review or a 👍 reaction lands ~1–5 min after open).
gh api repos/<owner>/<repo>/pulls/<PR>/reviews \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {state, submitted_at}'
gh api repos/<owner>/<repo>/pulls/<PR>/comments \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {id, path, line, body}'
```

If Codex left inline comments, triage every one via Step 11 (fix / explain / defer),
then reply and resolve. If Codex only reacted 👍 (no comments), note that and proceed.

> **Where the verdict lives — clean vs. findings come through different APIs:**
> - **Findings** → a formal review (`pulls/<PR>/reviews`, `state: COMMENTED`, carries
>   a `commit_id`) **plus** inline `pulls/<PR>/comments`. These are what you triage.
> - **A CLEAN round** → a PR **issue comment** (`issues/<PR>/comments`) whose body
>   starts with `Codex Review: Didn't find any major issues` — **not** a formal
>   review and **without** a `commit_id`.
>
> So **polling only `pulls/<PR>/reviews` will miss a clean pass** and look like
> "Codex hasn't responded" forever. Always also check `issues/<PR>/comments` for the
> "Didn't find any major issues" line. To confirm the verdict is on the *latest*
> commit when it's a clean issue-comment (no `commit_id`), reason from the timeline:
> the clean comment's `created_at` is after your last push / `@codex review`. Before
> merging, verify: CI green + `mergeStateStatus: CLEAN` + **0 unresolved review
> threads** + the latest Codex activity is either a clean comment or a resolved
> formal review on HEAD.

**The review is ITERATIVE — expect several rounds, not one.** Each round commonly
surfaces fresh P1/P2s as earlier ones are fixed (substantial PRs here have taken
**5–6 rounds / ~9 findings**). After every fix push: re-trigger `@codex review`,
wait, re-check, address. **Loop until a round comes back clean** (or remaining
items are explicitly deferred to tracked issues and their threads resolved) — only
then is the PR review-complete.

**Know when to stop — Codex findings have diminishing returns on mature code.** The
loop converges in *severity*: early rounds catch real bugs (correctness, ordering,
security); later rounds shrink to contrived sub-50ms timing interleavings or cosmetic
nits on already-correct code. One small, well-tested controller this session drew **5
sequential findings**, the last being "a trailing-space edit leaves untrimmed text in
the field until reload." Each fix is cheap, but a full PR→CI→Codex→(deploy→release→
scan) cycle *per nit* is not. Watch for the signature: repeated findings on the **same
file**, each needing a more elaborate/unlikely condition to trigger, on a low-priority
surface. When you see it:
- Prefer **one principled rewrite** (a small state machine / invariant — e.g. "drive
  state toward a single `target`") over another targeted patch. Patches to
  async/optimistic-UI behaviour keep leaking the *adjacent* interleaving; one correct
  model ends the whack-a-mole. (This session: abort → serialize → abandon-queue patches
  each surfaced the next edge; a convergence state machine subsumed them all.)
- **Surface the diminishing return to the user explicitly and recommend a stop** —
  merge-on-next-clean, or accept further nits as known/tracked rather than fix them.
  This is the user's call (it trades polish vs. cost); don't silently keep cycling, and
  don't silently stop. Codex *will* keep finding ever-smaller things — "clean" on a
  living controller is not guaranteed on any finite round.
- Once the user says "accept further nits / merge on clean," a new Codex comment is
  **resolved by acknowledgement** (reply that it's an accepted nit — fixed-later or
  won't-fix with the rationale — and resolve the thread). It does **not** gate the
  merge: branch protection gates on CI (`lint`/`test`) + `mergeStateStatus`, not on
  Codex. The agent normally never merges, but the repo owner can explicitly authorize a
  specific merge ("merge on clean") — that authorization is for that merge only.

Practical notes:
- **Codex drops rapid-fire triggers** — firing `@codex review` repeatedly in quick
  succession gets some coalesced/ignored. Space them out, poll patiently (~45s),
  and confirm via a review on the current HEAD sha / the trigger's reaction, not
  just elapsed time.
- **Codex can be slow or fail to auto-trigger** — it usually posts within ~1–5 min,
  but occasionally nothing appears for 10–15 min (or the auto-trigger never fires).
  In practice the auto-trigger is **unreliable enough to bake a nudge into the poll**:
  if there's no Codex activity ~5 min after a push, post one `@codex review` (spaced,
  not spammed) and keep polling. Don't merge on "green + silent Codex" when the user's
  gate is "Codex clean" — wait for the actual verdict.
- **Codex re-anchors ALREADY-RESOLVED inline comments to the new HEAD** on each
  re-review, so a naive "inline comments where `commit_id == HEAD`" filter resurfaces
  resolved findings as if they were new — every round. Dedupe by comment **`id`** and
  cross-check the review **thread `isResolved`** (the GraphQL `reviewThreads` query):
  a finding is new only if its id is unseen AND its thread is unresolved. A non-zero
  `inline_on_head` with `unresolved_count == 0` means "all re-anchored, nothing new" —
  safe to merge. (Bit me on every PR this session; treat `commit_id == HEAD` as "maybe
  shown again," never as "new.")
- **Background-poll the verdict, don't hand-loop** — when waiting on Codex, run a
  background poll that watches for *both* a formal review on HEAD (findings) *and*
  the clean issue-comment, with a generous deadline; re-trigger + re-poll if it
  times out silent.
- A finding can be valid but **already mitigated** (e.g. a release-scan flags a
  deploy risk you handled via a runbook step) — reply with the evidence and
  resolve; don't re-fix.

### Step 11: Respond to PR Review Comments

After the PR receives review comments (human **or** Codex), you **must** respond to every comment and resolve each conversation. Never leave comments unanswered.

#### 11a: Read all review comments

```bash
gh api repos/<owner>/<repo>/pulls/<PR_NUMBER>/comments \
  --jq '.[] | {id: .id, node_id: .node_id, path: .path, body: .body}'
```

#### 11b: Evaluate and act on each comment

For each comment, decide one of three responses:

- **Actionable:** Fix the code, commit, push, then reply referencing the commit hash.
- **Incorrect:** Reply with a clear technical explanation of why no change is needed.
- **Deferred:** Reply acknowledging the concern and stating which future effort or PR will address it.

> **Before replying "incorrect / already fixed", verify it — don't reason from
> memory or your working tree.** Codex's findings are frequently subtle and
> correct (this repo has seen a protocol-relative-URL open-redirect bypass and a
> Prawn AFM-font encoding crash caught only on re-review). Two failure modes to
> guard against:
> - *"Already fixed"* — confirm the fix is in the **pushed/merged** code
>   (`git show origin/<branch>:<path>`), not just edited locally. A dismissed-but-
>   real finding shipped unsafe code once this way.
> - *"False positive"* — reproduce the claim first. A 30-second probe
>   (`bin/rails runner`, a focused spec, a curl) settles it. Only after the probe
>   contradicts the finding do you reply "incorrect", and **quote the evidence**
>   (command + output) in the reply. If the probe confirms it, fix it.
> Expect several rounds; a fix can introduce a new (often higher-severity) finding.

#### 11c: Reply to each comment

The reply endpoint **requires the PR number** — omitting it
(`repos/<owner>/<repo>/pulls/comments/<COMMENT_ID>/replies`) returns
`HTTP 404: Not Found`:

```bash
gh api repos/<owner>/<repo>/pulls/<PR_NUMBER>/comments/<COMMENT_ID>/replies \
  -X POST \
  -f body='**Fixed in <commit-sha>.** <explanation of what was changed and why>'
```

#### 11d: Resolve all review threads

First, retrieve thread IDs:

```bash
gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <PR_NUMBER>) {
      reviewThreads(first: 20) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { path }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id, path: .comments.nodes[0].path}'
```

Then resolve each unresolved thread:

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "<THREAD_NODE_ID>"}) {
    thread { isResolved }
  }
}'
```

Multiple threads can be resolved in a single mutation by aliasing:

```bash
gh api graphql -f query='
mutation {
  t1: resolveReviewThread(input: {threadId: "<ID1>"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "<ID2>"}) { thread { isResolved } }
}'
```

### Step 12: Move Issue to Done (after merge)

```bash
gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <done-option-id>
```

### Step 13: Tag `main` & Publish Release (OPTIONAL — after merge)

If your project versions releases, tag/publish a release after the PR is merged to `main` (a human merges; the agent never does). Order: do this **immediately after merge**, then Step 12 (Done). Follow whatever release policy the project's development-workflow doc defines.

> **Fill out the CHANGELOG *before* you tag.** If the project keeps a curated
> changelog (e.g. `CHANGELOG.md`, Keep a Changelog format), add the new version's
> human-facing entry — and relabel any `[Unreleased]` section to the version being
> cut — **before** `gh release create`, so the tag captures it and the published
> notes and the changelog agree. A changelog edit that lands *after* the tag is a
> separate docs commit whose content the release notes never reference (and it does
> **not** warrant its own release tag — a docs-only changelog change ships nothing).
> Auto-generated release notes (`--generate-notes`) summarise merged PRs; they do
> **not** replace the curated changelog entry. Belongs in the **same PR** as the
> feature when practical, so the changelog merges with the code it describes.

```bash
git checkout main && git pull origin main
# Confirm the merge commit is present and its main CI/Deploy run is green.
# Confirm CHANGELOG.md carries this version's entry (see the note above).

# Idempotent: stop if the tag/release already exists.
gh release view <tag> --repo <owner>/<repo> >/dev/null 2>&1 \
  && echo "<tag> already released — skip" \
  || gh release create <tag> \
       --repo <owner>/<repo> --target main \
       --title "<release title>" \
       --generate-notes
```

`gh release create` creates the tag on `main` and publishes the release with auto-generated notes (merged PRs/commits since the previous tag). Record the tag + release URL in the audit log if your project keeps one.

### Step 14: Persist what's worth keeping (before the context resets)

Finishing a feature is the moment to **save anything worth saving from this
session** — the working memory you built up (hard-won gotchas, the *why* behind a
non-obvious decision, dead ends that mustn't be re-tried, a reusable
pattern/recipe) evaporates when the context is reset. Capture it where it will be
found again:

- **Agent memory** — durable, cross-session facts: a gotcha that cost real time, a
  decision and its rationale, a consciously-accepted limitation (with the
  trade-off), a recurring failure mode. Write the *non-obvious* part, not what the
  code/git already records. Update an existing memory rather than duplicating it.
- **Project documentation** — anything that belongs to the project, not just this
  session: architecture/flow changes and diagrams (the Step 8b mandate), the
  setup/recipe doc when a step changed, the design system when tokens/components
  changed, the CHANGELOG entry (Step 13). Put it **where it fits**, and link/cross-
  reference so it's discoverable.
- **Follow-ups** — anything deferred or discovered-but-out-of-scope → a tracked
  issue (don't leave it only in your head or a PR comment).

Rule of thumb: if a future you (or teammate) would have to re-derive it from
scratch after a reset, write it down now. This is cheap at the end of a feature
and expensive to reconstruct later.

## Quick Reference: Complete Flow

```
0.  feature-dev:code-explorer + code-architect (×2-3)  → Design pass (feature/multi-file; skip if trivial)
1.  gh issue create (+ open audit log if used)         → Create issue with plan (grounded in design pass)
2.  gh project item-add                                → Add to Kanban (Backlog)
3.  gh project item-edit                               → Move to Ready, then In Progress
4.  git checkout -b feature/                           → Create branch
5.  <implement the architect blueprint>                → Write code
5b. extend db/seeds.rb (+ bundle exec rails db:seed)   → Showcase-ready demo data
5c. /code-review (loop until clean; mind the stop rule) → Internal CR before push (skip if trivial)
6.  bundle exec rake                                   → Lint + tests + system tests
7.  git commit (+ append sha to audit log)             → Overcommit hooks validate
8.  /product-review (or /verify, or agent-browser+curl) → Live verification (curl Set-Cookie scope for auth/cookie changes)
9.  git push + gh pr create                            → Push and open PR (Closes #N)
10. gh project item-edit                               → Move to In Review
10b. wait for + check Codex review (proactively!)      → chatgpt-codex-connector[bot]
11. gh api .../comments (+ log replies in audit log)   → Reply + resolve threads (human + Codex)
12. <human rebase-and-merges the PR to main>           → Merge
13. fill CHANGELOG → gh release create (OPTIONAL)      → Changelog entry FIRST, then tag main + publish
14. gh project item-edit + final summary in audit log  → Move to Done
15. save to agent memory + project docs + follow-ups   → Persist what's worth keeping before context reset
```