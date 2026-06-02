---
name: qa-remediation
description: Process a batch of review findings (from /qa-review, /security-review, /ux-review, /ui-polish, /ui-designer, /code-review, PR review comments, or any audit report) into tracked GitHub issues and atomic fix commits on the current branch. Use this skill as soon as a review phase surfaces findings the user wants to act on, or when they say "remediate", "fix the findings", "work through the review", "create issues for each finding", "address these findings", "apply the review". Always creates one GitHub issue per finding (including ones deferred for later) so the audit trail is complete; explicitly asks the user which findings to fix this round; commits each fix atomically with the issue number as the first token of the subject ("#123 Short description"); closes each issue immediately after its commit is pushed. Unlike /execution-plan this skill stays on the current branch and skips PR creation + Kanban lifecycle — use /execution-plan for single-bug work, new features, or anything that needs its own branch and PR.
---

# QA Remediation

Turn a list of review findings into tracked GitHub issues and atomic fix commits on the current branch. Every finding gets an issue so the audit trail is complete; only the findings the user approves get a fix commit.

## When to use

- **After** any review skill (`/qa-review`, `/security-review`, `/ux-review`, `/ui-polish`, `/ui-designer`, `/product-review`, `/code-review`) produces a findings report and the user wants to act on it.
- **When** a PR receives multiple review comments that map cleanly to discrete fixes.
- **When** the user asks to "work through these findings", "remediate", "address the review items", or similar.

**Do not use this skill for:**

- A single bug fix with no prior review artifact → `/execution-plan`.
- New features → `/execution-plan`.
- Work that needs a dedicated branch or PR → `/execution-plan`.
- Architectural changes that span many branches → a full plan, not a remediation round.

## Relationship to /execution-plan

| Step | /execution-plan | /qa-remediation |
|------|------------------|------------------|
| Create issue per unit of work | ✔ | ✔ (one per finding, always) |
| Kanban lifecycle | ✔ | ✗ |
| Create feature branch | ✔ | ✗ (stays on current branch) |
| Atomic commits + overcommit hygiene | ✔ | ✔ |
| Runtime / live verification | ✔ | ✔ (on request or after the last fix) |
| Create PR | ✔ | ✗ (the PR already exists, or the branch isn't ready) |
| Close each issue after commit | — | ✔ |

Everything shared (issue-first, commit discipline, overcommit handling, GitHub CLI auth) behaves the same way.

## GitHub CLI authentication

Always prefix `gh` calls with `unset GITHUB_TOKEN &&`. A stale env token can produce `HTTP 401: Bad credentials`; unsetting it lets the CLI fall back to its own auth store.

## Workflow

### Step 1 — Present findings and ask what to fix

Before doing anything, lay out the findings as a short table so the user can see them all at once. Include:

- **ID** (C1, H3, etc. — whatever the review used, or synthesise IDs if the review didn't).
- **Severity** (🔴 Critical / 🟠 High / 🟡 Medium / 🟢 Low).
- **Title** (one line).
- **Source** (review report name + finding ID + affected file).

Then ask two explicit questions:

1. **Which findings get a fix in this pass?** Accept answers like "all", "all Critical", "C1–C3", an explicit list, or "none" (tracking only).
2. Implicitly: **every finding not in that list gets an issue for tracking only.** Call this out so the user knows deferred items won't be forgotten.

Every finding gets a GitHub issue. That rule is non-negotiable — the audit trail must be complete even for work you're deferring. Do not ask the user whether to create an issue; only ask whether to fix it.

### Step 2 — Create issues (all findings, in parallel)

Run one `gh issue create` per finding. Since they're independent, send them in a single message with multiple tool calls so they run in parallel.

```bash
unset GITHUB_TOKEN && gh issue create \
  --repo <owner>/<repo> \
  --title "<descriptive title>" \
  --label "<label>" \
  --body "$(cat <<'EOF'
## Summary
<one-paragraph description of the finding>

## Source
<review report path, finding ID, affected file:line>

## Repro or evidence
<minimal steps, log excerpt, or quote from the review>

## Scope
<files a fix would touch, and the shape of the intended change>

## Verification
<how we'll confirm it's fixed (spec, manual check, etc.)>
EOF
)"
```

**Label picks:**
- `bug` for defects that break existing behaviour.
- `enhancement` for improvements, hardening, UX polish.
- `documentation` for docs-only.
- `cleanup` for refactors.

**For findings being deferred** (tracked-only, not fixed this round), add this block at the bottom of the body so future readers know the state:

```markdown
## Deferred
Tracked for visibility. Not scheduled in the current remediation round.
Reason: <product decision / scope / owner / etc.>
```

Capture each returned issue number — you need it for the commit titles.

### Step 3 — Fix each will-fix finding atomically

Work the will-fix list in severity order (Critical → High → Medium → Low). Within a severity bucket, do small independent changes first and save shared-file changes for last so you only re-read the surrounding code once.

For each finding:

1. **Implement the scoped change.** Do not piggyback unrelated cleanup. If the fix grows beyond one coherent change, stop and open a follow-up issue for the rest — atomic means atomic.
2. **Run the project's pre-commit gates** appropriate to the change:
   - Ruby / Rails: run the project's lint and test rake tasks (e.g. `bundle exec rake`), including system tests if any UI or integration surface changed. If your Ruby version manager needs activation (rbenv/mise/etc.), prefix Ruby commands accordingly.
   - For other stacks, use the equivalent local checks.
   - Running only the specs closest to the change is fine during iteration; a full run before the last push is wise.
3. **Commit.** The subject MUST start with the issue number (details below).
4. **Push** the branch.
5. **Close the issue** with a comment linking to the commit.

Close each issue immediately after its push, not batched at the end. The open-issue list then always reflects outstanding work.

### Commit title format

The issue number is the first token of the subject. This is the whole reason for the convention: git log becomes grep-able back to issues, and issues become grep-able back to git log.

**Preferred shape:**

```
#<N> <Capitalised action verb> <what changed>
```

Example:

```
#123 Fix off-by-one in pagination guard
```

**If the project uses Conventional Commits**, use instead:

```
[#<N>] fix(scope): short description
```

Either shape works; pick what matches the project's existing history. Either way, `#N` (or `[#N]`) is the first grep-able token.

**Body of the commit message** explains the **why** — root cause, constraint, prior incident, reasoning — not just what changed. End with `Closes #<N>.` on its own line so GitHub auto-closes the issue if the branch is merged via PR:

```
#123 Fix off-by-one in pagination guard

The guard compared page index against count instead of count - 1, so the
last page rendered an empty result set and a stray "next" link. Adjusted
the boundary and added a spec covering the final page.

<remaining prose...>

Closes #123.
```

**Overcommit compatibility:** the `#` prefix does not break `CapitalizedSubject` hooks, which look at the first *alphabetical* character (here `F` in "Fix"). Same for subject-length checks — they count characters, not meaning.

If a hook flags a genuine false positive, skip only the specific hook and document the reason in the commit body:

```bash
SKIP=<HookName> git commit -m "..."
```

Never `OVERCOMMIT_DISABLE=1`. That disables every hook silently and is indistinguishable from sloppy work in the log.

Use `[skip ci]` in the subject (or body) for changes that genuinely don't need CI — docs-only, comment-only, non-runtime config. When in doubt, let CI run.

### Step 4 — Push and close

After each atomic commit:

```bash
unset GITHUB_TOKEN && git push

unset GITHUB_TOKEN && gh issue close <N> --repo <owner>/<repo> \
  --comment "Fixed in \`<short-sha>\`. <one-sentence summary>. <PR link if one exists>."
```

The close-comment should name the commit SHA so anyone reading the issue later can find the change in one click.

**Do not close deferred issues.** They stay open with the `## Deferred` body until someone picks them up in a later round.

### Step 5 — Wrap up

When the will-fix list is empty:

1. **Append a short audit entry** to the project's running log if it keeps one (e.g. a per-effort `Steps.md`). Record each issue number, the commit SHA, and the final status.
2. **Summarise for the user** in one short table: issue → commit → status (fixed / deferred).
3. **Mention the PR status** if the branch has an open PR — the new commits landed, and the PR should be re-requested for review.
4. **Hand off open deferred issues**: the user may want to add them to a backlog milestone or a future tracking issue.

## Ordering rules

- Severity order: Critical → High → Medium → Low.
- Within severity: smaller, independent, single-file changes first; shared-file or cross-cutting changes last.
- If two findings touch the same file and the same function, commit them together only if the split would make the diff nonsensical — and even then, the commit subject must call out both issue numbers: `#104 #107 Short description`. Bundling is a last resort, not a convenience.

## Edge cases

- **A review finding turns out to be wrong on closer inspection.** Close the issue with `--reason "not planned"` and a short technical explanation. Do not leave wrong findings open to rot.
- **A fix grows mid-implementation.** Stop. Commit what you have that is correct and complete. Open a follow-up issue for the remainder. The half-finished work does not go in.
- **The change requires database migration, data backfill, or a feature flag.** Those are rarely single-commit work — stop and escalate to `/execution-plan` for a proper PR with staged review.
- **The current branch is shared or protected.** Do not push partial remediation onto a branch other people are using. Switch to `/execution-plan` and open a dedicated remediation branch + PR.
- **The current branch is not behind a PR yet.** Fine — the skill still works. Mention at wrap-up that the user will need to open the PR via `/execution-plan` when the remediation round is complete.

## Quick reference

```
show findings table (ID, severity, title, source)
ask: which findings get a fix this pass
  → all others are deferred (issue-only)

create one gh issue per finding (in parallel)
  → deferred issues include a "## Deferred" body section

for each will-fix finding, in severity order:
  implement the scoped change
  run project pre-commit checks
  git commit -m "#N <Capitalised action>"     # overcommit hooks run
  git push
  gh issue close N --comment "Fixed in <sha>. ..."

append audit entry (project's running log, if it keeps one)
print one summary table for the user
```

## Example turn

**User:** "The /qa-review just finished. There are 6 Critical findings. Fix them."

**Skill output:**

1. Extract the 6 findings from the review report.
2. Render a numbered table:

   | ID | Sev | Title | Source |
   |----|-----|-------|--------|
   | C1 | 🔴 | Null-byte input crashes endpoint with 500 | QA D1, `app/models/example.rb:22` |
   | C2 | 🔴 | Login redirects use 302 instead of 303 | QA D2, `app/misc/rodauth_main.rb:84` |
   | … | | | |

3. Ask: "Fix all 6? Or a subset? Any you want to defer to a follow-up?"
4. On "fix all 6", create 6 issues in parallel via `gh issue create`.
5. Work C1 → C6 in order, one atomic commit per fix, close each issue after push.
6. After C6 is closed, append a section to the project's running log summarising issue → commit → status, and show the same table to the user.

---

## Triggering notes

This skill is best invoked explicitly by name; prose-based auto-triggering is unreliable for procedure skills built from primitives Claude already has.
