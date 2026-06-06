---
name: execution-plan
description: Drive the end-to-end execution of any coherent piece of code work in this project — from issue creation, through branching, implementation, testing, live verification, PR, and review response. Trigger whenever the user asks to implement a feature, fix a bug, refactor code, ship a change, or act on a plan that will produce commits. Also trigger when they say "start work", "new feature", "fix issue", "create PR", "push changes", "let's implement", "execute the plan", or reference a planning document that needs to be carried out. Keeps the loop intact — GitHub issue first, then Kanban move, then branch, then atomic commits, then live product verification, then PR, then review response — none of the steps silently drop.
---

# Execution Plan

This skill enforces the full development workflow defined in the project's development-workflow doc (e.g. AGENTS.md / CLAUDE.md). Every coherent piece of code work follows this lifecycle: Issue → Kanban → Branch → Implement → Test → Live Verify → Push → PR → Review → Respond → Resolve.

## Why This Matters

Skipping steps (especially GitHub issues, Kanban updates, and live testing) creates tracking gaps and lets runtime bugs slip through. The automated test suite catches logic errors but not rendering issues, broken layouts, or Phlex/ERB integration problems. Live verification regularly catches runtime errors (e.g. a `Phlex::ArgumentError`) that unit and system tests miss.

## GitHub CLI Authentication

The `GITHUB_TOKEN` environment variable can override keyring-based authentication and cause failures. Always prefix `gh` commands with `unset GITHUB_TOKEN &&`:

```bash
unset GITHUB_TOKEN && gh issue create ...
unset GITHUB_TOKEN && gh pr create ...
unset GITHUB_TOKEN && gh project item-add ...
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
unset GITHUB_TOKEN && gh project field-list <project-number> --owner <owner> --format json
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
| 13 (release) | release tag + release URL, if the project versions releases |
| 12/14 (done) | final summary table: issue → commit → release → status |

**Tone.** Factual, short. The audience is future-you (or a reviewer) reconstructing what decisions were made, not re-arguing them.

## Workflow Steps

### Step 1: Create GitHub Issue

Before writing any code, create an issue with a detailed plan:

```bash
unset GITHUB_TOKEN && gh issue create \
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
unset GITHUB_TOKEN && gh project item-add <project-number> --owner <owner> --url <issue-url>
```

The issue starts in **Backlog** by default. Save the item ID from the output (or retrieve it later with `gh project item-list`).

### Step 3: Move to Ready, Then In Progress

To move an issue on the board, you need its **item ID**. Retrieve it:

```bash
unset GITHUB_TOKEN && gh project item-list <project-number> --owner <owner> --format json \
  | jq -r '.items[] | select(.content.number == <ISSUE_NUMBER>) | .id'
```

Then update the status (option IDs from `gh project field-list`, see Project References):

```bash
# Move to Ready (before starting work)
unset GITHUB_TOKEN && gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <ready-option-id>

# Move to In Progress (when starting work)
unset GITHUB_TOKEN && gh project item-edit \
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

Write code, following project conventions. If your Ruby version manager needs activation (rbenv/mise/etc.), prefix Ruby commands accordingly.

**For any UI work** (new views, components, forms, layouts, styling changes), use the `/ui-designer` skill. It provides access to the Tailwind CSS reference library and ensures consistency with the project design system (the `ha-*` CSS design-token system). Always check the library before building new components from scratch.

### Step 5b: Seed data (Mandatory for any new user-facing surface)

Extend `db/seeds.rb` so that after `bin/rails db:seed` a developer can sign in and **immediately showcase and play with** the surface this phase adds — no manual record-building. See the project's `AGENTS.md` §8 for the full rule. In short:

- **Comprehensive states** — seed records across the meaningful states the surface renders (lifecycle states, with/without optional data, an empty case).
- **Idempotent** — `find_or_create_by` keyed on a natural attribute; re-running never duplicates.
- **Production-guarded** — keep `return if Rails.env.production?` (`db:prepare` auto-seeds a fresh DB).
- **Tenancy-aware** — provision the demo tenant via the tenant-creation action, `Apartment::Tenant.switch` for tenant-scoped records, and guard the demo to the base schema (`return unless Apartment::Tenant.current == "public"`).
- **Loginable** — seeded sign-in accounts need a verified status; note the demo email + org subdomain in a comment.
- **Verify** — run `bin/rails db:seed` twice (idempotency) and confirm the records render during Step 8 (`/product-review`).

### Step 6: Pre-Commit Validation

Run the project's lint/test/system-test tasks and ensure they all pass before committing. Many Rails projects expose these as rake tasks; run everything at once with:

```bash
bundle exec rake
```

If the project splits them out (e.g. fix-lint, lint, tests, system-tests tasks), run each in turn. Confirm the task names against the project's Rakefile rather than assuming they exist.

### Step 7: Commit (Atomic Commits Required)

**NEVER bundle all changes into a single giant commit.** Each commit must be:

- **Atomic:** One logical change per commit (e.g., "harden pagination", "fix policy bypass", "add comment edit UI" are three separate commits, not one)
- **Focused:** Only files related to that one change are included
- **Reversible:** Any commit can be reverted independently without breaking other changes
- **Buildable:** Each commit passes lint and tests on its own

When implementing a multi-part feature, commit after each logical unit is complete and green. Run the project's lint + test tasks before each commit.

Stage specific files (not `git add .`) and use a descriptive commit message. Overcommit hooks will enforce RuboCop, trailing whitespace, and commit message format (capitalized subject, no trailing period).

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

**`[skip ci]` flag:** Add `[skip ci]` to commit messages when the change does not need CI. This includes documentation-only commits (`.md` files, skill files, workflow docs), comment-only code changes, and non-runtime config changes. Place it at the end of the subject line or in the commit body.

### Step 8: Runtime Test Workflow

After committing and before pushing, perform live verification. Use the `/product-review` skill for the full checklist, or manually:

```bash
bin/cli app rebuild
bin/cli app restart
bin/cli mail start
```

Then use `agent-browser` to verify all pages render without errors. Fix any issues found, commit the fix, and re-run the test suite.

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

### Step 9: Push and Create PR

```bash
unset GITHUB_TOKEN && git push -u origin <branch-name>
```

Create the PR with a summary and test plan:

```bash
unset GITHUB_TOKEN && gh pr create \
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
unset GITHUB_TOKEN && gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <in-review-option-id>
```

### Step 11: Respond to PR Review Comments

After the PR receives review comments, you **must** respond to every comment and resolve each conversation. Never leave comments unanswered.

#### 11a: Read all review comments

```bash
unset GITHUB_TOKEN && gh api repos/<owner>/<repo>/pulls/<PR_NUMBER>/comments \
  --jq '.[] | {id: .id, node_id: .node_id, path: .path, body: .body}'
```

#### 11b: Evaluate and act on each comment

For each comment, decide one of three responses:

- **Actionable:** Fix the code, commit, push, then reply referencing the commit hash.
- **Incorrect:** Reply with a clear technical explanation of why no change is needed.
- **Deferred:** Reply acknowledging the concern and stating which future effort or PR will address it.

#### 11c: Reply to each comment

```bash
unset GITHUB_TOKEN && gh api repos/<owner>/<repo>/pulls/comments/<COMMENT_ID>/replies \
  -X POST \
  -f body='**Fixed in <commit-sha>.** <explanation of what was changed and why>'
```

#### 11d: Resolve all review threads

First, retrieve thread IDs:

```bash
unset GITHUB_TOKEN && gh api graphql -f query='
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
unset GITHUB_TOKEN && gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "<THREAD_NODE_ID>"}) {
    thread { isResolved }
  }
}'
```

Multiple threads can be resolved in a single mutation by aliasing:

```bash
unset GITHUB_TOKEN && gh api graphql -f query='
mutation {
  t1: resolveReviewThread(input: {threadId: "<ID1>"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "<ID2>"}) { thread { isResolved } }
}'
```

### Step 12: Move Issue to Done (after merge)

```bash
unset GITHUB_TOKEN && gh project item-edit \
  --project-id <project-id> \
  --id <ITEM_ID> \
  --field-id <status-field-id> \
  --single-select-option-id <done-option-id>
```

### Step 13: Tag `main` & Publish Release (OPTIONAL — after merge)

If your project versions releases, tag/publish a release after the PR is merged to `main` (a human merges; the agent never does). Order: do this **immediately after merge**, then Step 12 (Done). Follow whatever release policy the project's development-workflow doc defines.

```bash
git checkout main && git pull origin main
# Confirm the merge commit is present and its main CI/Deploy run is green.

# Idempotent: stop if the tag/release already exists.
unset GITHUB_TOKEN && gh release view <tag> --repo <owner>/<repo> >/dev/null 2>&1 \
  && echo "<tag> already released — skip" \
  || unset GITHUB_TOKEN && gh release create <tag> \
       --repo <owner>/<repo> --target main \
       --title "<release title>" \
       --generate-notes
```

`gh release create` creates the tag on `main` and publishes the release with auto-generated notes (merged PRs/commits since the previous tag). Record the tag + release URL in the audit log if your project keeps one.

## Quick Reference: Complete Flow

```
1.  gh issue create (+ open audit log if used)         → Create issue with plan
2.  gh project item-add                                → Add to Kanban (Backlog)
3.  gh project item-edit                               → Move to Ready, then In Progress
4.  git checkout -b feature/                           → Create branch
5.  <implement changes>                                → Write code
5b. extend db/seeds.rb (+ bundle exec rails db:seed)   → Showcase-ready demo data
6.  bundle exec rake                                   → Lint + tests + system tests
7.  git commit (+ append sha to audit log)             → Overcommit hooks validate
8.  /product-review                                    → Live browser verification
9.  git push + gh pr create                            → Push and open PR (Closes #N)
10. gh project item-edit                               → Move to In Review
11. gh api .../comments (+ log replies in audit log)   → Reply + resolve threads
12. <human rebase-and-merges the PR to main>           → Merge
13. gh release create (OPTIONAL)                       → Tag main + publish release
14. gh project item-edit + final summary in audit log  → Move to Done
```
