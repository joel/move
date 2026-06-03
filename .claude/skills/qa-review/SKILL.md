---
name: qa-review
description: Use this skill after product-review completes to perform structured quality assurance on the full feature or fix — checking edge cases, boundary conditions, and regression risk that automated tests may not cover. Trigger when the user says "qa review", "qa check", "edge case review", or after any phase completes before the PR is merged. This skill is adversarial — its job is to break the feature, not validate it. Always prefer testing in the live Docker environment over reading code.
---

# QA Review

Perform structured quality assurance on the changes in the current branch. This is an adversarial pass — attempt to break the feature through edge cases, unexpected input, and user behaviour the implementation agent didn't anticipate.

## Project Context

- **App URL:** `https://<app-host>/`
- **Mail URL:** `https://<mail-host>/`
- **Container:** `<app-container>`
- **CLI:** Use `bin/cli` for app/service management (`bin/cli app rebuild`, `bin/cli app restart`, `bin/cli mail start`)
- **Ruby commands outside container:** run with plain `bundle exec ...` (activate your version manager first if your setup requires it)
- **Auth framework:** Rodauth (login, create-account, verify-account, email-auth, webauthn)
- **Authorization:** ActionPolicy (`authorize!` in controllers, `allowed_to?` in views)
- **Views:** Phlex components (not ERB)

## Seed Data Reference

The database is populated from `db/seeds.rb`. Read it before testing and use the seeded records — do NOT create test data from scratch unless you are specifically testing creation flows.

From `db/seeds.rb`, identify:
- **Seeded accounts and their roles** — which users exist, and what authorization level each holds (admin, member-with-write, member-read-only, non-member).
- **The key resources and their states** relevant to the change you are reviewing — which records exist, and what lifecycle state each is in.
- **The role/state matrix that applies to your domain** — for each combination of role and resource state, what should be permitted (read, write, comment, delete) and what should be blocked.

Capture this as a small table for your own reference before you start, so you know which seeded record exercises each branch of the feature's authorization and state logic.

### Test Across Roles (template)

Pick one seeded account per access level and run the feature as each:
1. **Superadmin** — should have full access.
2. **Member with write access** — should have member-level access to resources they belong to.
3. **Member with read-only access** — should be able to view but not mutate.
4. **Non-member** — should be denied access to resources they don't belong to.

### Test Across States (template)

Many resources gate writability/visibility on a lifecycle state. Identify the states in your domain and test the feature against at least:
1. A **writable** resource (a state where create/edit is allowed).
2. A **read-only-but-visible** resource (a state where content is viewable/commentable but not editable).
3. A **locked** resource (a state where the resource is neither writable nor commentable).

### Login Helper

Seeded users authenticate via email auth (magic link) caught by the mail host. Replace `<seed-user-email>` with a seeded account at the role you want to test.

```bash
curl -sk -X DELETE https://<mail-host>/messages
agent-browser open https://<app-host>/login && agent-browser wait --load networkidle
agent-browser snapshot -i  # Find email and Login button refs
agent-browser fill @eN "<seed-user-email>"
agent-browser click @eM && agent-browser wait --load networkidle
sleep 2
LOGIN_KEY=$(curl -sk https://<mail-host>/messages/1.plain | grep -oP 'key=\K\S+')
agent-browser open "https://<app-host>/email-auth?key=$LOGIN_KEY" && agent-browser wait --load networkidle
agent-browser snapshot -i  # Find Login button
agent-browser click @eN && agent-browser wait --load networkidle
```

### Rails Runner Helper

```bash
cat > /tmp/qa-check.rb <<'RUBY'
# Replace with your check
puts SomeModel.pluck(:id).first
RUBY
docker exec -i <app-container> bin/rails runner - < /tmp/qa-check.rb
```

## Prerequisites

- App running in Docker (`bin/cli app start` or `bin/cli app restart`)
- `agent-browser` and `curl` available
- Mail service running (`bin/cli mail start`)
- Seed data loaded (`db:seed` or `db:reset`)

## Step 1: Understand the Feature

Read the GitHub issue and the diff to understand what was built:

```bash
unset GITHUB_TOKEN && gh issue view <ISSUE_NUMBER>
git diff main...HEAD --stat
```

Identify:
- The happy path (what the feature does when everything goes right)
- The inputs (forms, URL params, API calls, events)
- The side effects (emails, DB writes, redirects, events)

## Step 2: Verify the Happy Path

Run through the acceptance criteria using seeded data. Use seeded records and users rather than creating new ones.

**Test across resource states** — every feature that interacts with a state-gated resource should be tested on at least 3 records:
1. A **writable** resource (a state allowing create/edit)
2. A **read-only-but-visible** resource (viewable/commentable, not editable)
3. A **locked** resource (neither writable nor commentable)

**Test across user roles:**
1. **Superadmin** — should have full access
2. **Member with write access** — should have member-level access
3. **Member with read-only access** — should have read-only access
4. **Non-member** — use a seeded account on resources it is not a member of

## Step 3: Test Edge Cases

For every input or trigger, test the following:

### Empty / Missing Input
- Submit forms with required fields blank
- Send requests with missing params (use curl directly)
- Test with nil/empty URL params

### Boundary Values
- Text fields at maximum length
- Unicode-only names (e.g., non-Latin scripts, emoji)
- Numbers at 0, negative, extremely large
- Dates in the past, today, far future

### Concurrent / Repeated Actions
- Double-click submit buttons
- Refresh mid-flow
- Duplicate submissions (same email/token used twice)
- A uniqueness- or rate-limited action repeated (perform the same gated action twice and confirm the second is rejected)

### Unauthorized Access
- Logged-out user accesses protected URL directly
- Non-member accesses a resource directly by ID/UUID
- Read-only user tries to create/edit/delete content
- User A accesses User B's resources

### State-Dependent Behavior (use seeded records!)
List the relevant records and their states, then verify the feature on each:

```bash
# List seeded records and their states (adjust model/columns to your domain)
cat > /tmp/qa-states.rb <<'RUBY'
SomeModel.all.each { |r| puts "#{r.state.to_s.ljust(10)} #{r.id}" }
RUBY
docker exec -i <app-container> bin/rails runner - < /tmp/qa-states.rb
```

Verify the feature behaves correctly in each state — writable states allow mutation, read-only states block edits but permit viewing/commenting, locked states block everything.

### Authorization Matrix Testing
For features with role-based access, test the full matrix:

```
| Action | superadmin | member (write) | member (read-only) | non-member |
|--------|-----------|----------------|--------------------|------------|
| index  | ?         | ?              | ?                  | ?          |
| show   | ?         | ?              | ?                  | ?          |
| create | ?         | ?              | ?                  | ?          |
| edit   | ?         | ?              | ?                  | ?          |
| delete | ?         | ?              | ?                  | ?          |
```

Use seeded users for each role. Log in as different users via the email auth flow.

## Step 4: Verify Side Effects

### Emails
```bash
curl -sk https://<mail-host>/messages \
  | python3 -c "import json,sys; [print(m['id'],m['subject'],m['recipients']) for m in json.load(sys.stdin)]"
```

### Database State
```bash
cat > /tmp/qa-check.rb <<'RUBY'
record = MyModel.last
puts record.attributes.slice("id", "status").inspect
RUBY
docker exec -i <app-container> bin/rails runner - < /tmp/qa-check.rb
```

### Redirects & Flash Messages
Verify the user lands on the correct page after each action and sees appropriate feedback.

## Step 5: Mobile Testing (Mandatory)

Desktop-passing features frequently break on mobile — buttons can stop responding, content can overflow, and touch targets can be too small. Test the full app at mobile width (393x852) for every QA pass that touches any UI.

Read `references/mobile_testing.md` for the page-by-page test matrix, overflow detection command, the touch-target verification script (flags any element under 44x44), mobile-specific defect patterns, and the report template.

## Step 6: Regression Check

Test the features most likely broken by this change. Use seeded data for efficiency:

- **Core resource CRUD**: View/edit a seeded record
- **Nested/related content**: View a seeded record with its associated child records (images, comments, reactions, etc.)
- **Authentication**: Log in/out via email auth using a seeded user
- **Comments & reactions** (if applicable): Verify existing seeded comments/reactions render
- **Membership/roles**: Verify seeded memberships display correctly

## Step 7: Run Automated Tests

Run the project's test, system-test, and lint rake tasks (e.g. `bundle exec rake`). Check the project's Rakefile/README for the exact task names if a bare `rake` does not cover all three.

## Output Format

Write the report to your project's review-notes location (e.g. a `QA-Review.md` alongside the plan):

```markdown
# QA Review -- <branch name>

**Branch:** `<branch>`
**Date:** YYYY-MM-DD
**Reviewer:** Claude (adversarial QA pass)

---

## Test Suite Results

- **Full test suite:** N examples, 0 failures, N pending
- **Linting:** N files, no offenses

---

## Acceptance Criteria

- [x] <criterion> -- PASS
- [ ] <criterion> -- FAIL: <details>

---

## Defects (must fix before merge)

### D1: <title>
**File:** `path:line`
**Steps to reproduce:** ...
**Expected:** ...
**Actual:** ...
**Recommended fix:** ...

---

## Edge Case Gaps (should fix or document)

### E1: <title>
**Risk if left unfixed:** ...
**Recommendation:** ...

---

## Observations

- <notable findings that aren't defects>

---

## Regression Check

- **Core resource CRUD** -- PASS/FAIL
- **Nested/related content** -- PASS/FAIL
- **Authentication** -- PASS/FAIL
- **Comments & reactions** -- PASS/FAIL
- **Membership/roles** -- PASS/FAIL

## Mobile (393x852)

| Page | Overflow | Buttons | Touch Targets | Notes |
|------|----------|---------|---------------|-------|
| Home | ? | ? | ? | |
| Login | ? | ? | ? | |
| Index | ? | ? | ? | |
| Show | ? | ? | ? | |
| Form/detail | ? | ? | ? | |
| Admin | ? | ? | ? | |
```

## Fixing Defects

For each Defect, open a fix before the PR is merged. Follow the project's commit conventions. Add a regression spec if the defect is logic-based.

For Edge Case Gaps, ask the user: fix now or create a follow-up issue?
