---
name: product-review
description: Use after committing code changes to perform mandatory live product verification. Triggers when the user says "product review", "test live", "runtime test", "verify live", "browser test", or after completing a feature/fix. Rebuilds the app, restarts services, and visually verifies every changed surface with agent-browser using seed data.
---

# Product Review Workflow

Perform live product verification of the application after code changes. This ensures the app actually works in the Docker environment, not just in unit tests.

This skill is domain-agnostic. It does not assume what your app does — it gives you a repeatable loop to apply to whatever surfaces your branch changed. The shared stack assumed throughout is: Rails, Phlex views, Rodauth (email/passwordless auth), Active Storage, a PWA service worker, and the `bin/cli` tooling.

## When to Run

Run this workflow:
- After all code changes are committed and tests pass
- Before pushing a branch or creating a PR
- When the user asks to "test live" or "verify in browser"

## Prerequisites

- `agent-browser` CLI installed and available
- Docker services running (app + mail)
- The `bin/cli` command available in the project root
- (Optional) If the project uses a Ruby version manager, activate it before running `bundle exec` commands.

## Seed Data Reference

Use the project's own seed data (`db/seeds.rb`). Do NOT create test accounts from scratch — prefer existing seeded records, and only create new data when no seeded record exercises the change.

Before verifying, open `db/seeds.rb` and identify:

- **Accounts and roles** — which seeded emails exist, and what role/permission level each has (e.g. an admin/superadmin account plus one or more lower-privilege accounts). Note at least one account per distinct role you need to test.
- **Key resources and their states** — the primary domain records the change touches, and the distinct states/variants they can be in (e.g. one record per lifecycle state, one with attachments, one empty). You want coverage of each state your change can render or affect.
- **Downstream artifacts** — any seeded records that represent side effects (emails, jobs, exports, invitations, etc.) relevant to the change.

Record the concrete emails/IDs you'll use as `<seed-user-email>`, `<seed-admin-email>`, and `<resource-id>` placeholders throughout the steps below.

### Login Helper

Auth is email/passwordless via Rodauth, with MailCatcher capturing the email. To log in as any seeded user:

```bash
# 1. Clear old emails
curl -sk -X DELETE https://<mail-host>/messages

# 2. Go to login page, fill email, submit
agent-browser open https://<app-host>/login && agent-browser wait --load networkidle
agent-browser snapshot -i  # Find email field and Login button refs
agent-browser fill @eN "<seed-user-email>"
agent-browser click @eM  # Login button
agent-browser wait --load networkidle

# 3. Get login link from email and navigate
sleep 2
LOGIN_KEY=$(curl -sk https://<mail-host>/messages/1.plain | grep -oP 'key=\K\S+')
agent-browser open "https://<app-host>/email-auth?key=$LOGIN_KEY" && agent-browser wait --load networkidle

# 4. Click the Login button on the email-auth page
agent-browser snapshot -i  # Find Login button ref
agent-browser click @eN  # Login button
agent-browser wait --load networkidle
```

## Workflow

### Step 1: Rebuild and Restart

```bash
bin/cli app rebuild
bin/cli app restart
bin/cli mail start
```

Wait for the health check to pass in the restart output before proceeding.

### Step 2: Determine What Changed

Find the surfaces your branch touches so you know what to verify:

```bash
git diff main...HEAD --name-only
```

Map the changed files to user-facing surfaces (views, controllers, routes, components, mailers, jobs, service worker, manifest). Every changed surface must be verified live below.

### Step 3: Per-Surface Verification Loop

For **each page/surface changed by this branch**, run this loop:

```bash
agent-browser open "https://<app-host>/<path>" && agent-browser wait --load networkidle
agent-browser screenshot /tmp/rt-<surface>.png
# Confirm the page renders without errors (no 500 page, no error backtrace, expected content present)
agent-browser eval "document.title"
```

For each surface, verify:
- It renders without runtime errors (no exception page, no broken layout).
- **Logged-out state** — what an anonymous visitor sees (redirect to login, public content, or access prompt).
- **Logged-in state** — content for an authenticated user.
- **Each relevant role** — repeat as every role whose access or view differs (admin vs. non-admin, owner vs. member, etc.). Verify role-gated UI appears/disappears correctly.

Always exercise these generic surfaces if the branch touches them or their shared layout/nav:

- **Home / landing page** (logged out and logged in) — nav/sidebar renders, primary calls-to-action present.
- **Auth / login page** — email field + submit button, the login helper flow works end to end.
- **An index page** — the list/collection view for an affected resource renders all expected items.
- **A show page** — the detail view for a single affected record, including its associated content and action buttons.
- **An admin page** — any management/admin surface affected (user list, requests, settings, etc.), gated to admin roles.

### Step 4: Test Dark Mode

```bash
agent-browser snapshot -i
# Find and click the "Toggle dark mode" button
agent-browser click @eN  # Dark mode toggle
agent-browser wait 500 && agent-browser screenshot /tmp/rt-dark-mode.png
```

Verify: dark background, light text, cards/components adapt correctly on every changed surface.

### Step 5: Cleanup (between role passes / at end)

```bash
agent-browser close
```

## Verify User Journeys (Critical)

Page rendering alone does not guarantee correctness. Test the multi-step user journeys your change affects, including **downstream effects** (emails sent, jobs enqueued, records created, state transitions).

Pattern for verifying a journey:

1. Perform the first user action in the browser; confirm the immediate UI feedback (flash/toast, Turbo Stream update, redirect).
2. Check downstream side effects: inspect MailCatcher for any email that should have been sent, check Rails logs for enqueued/processed jobs, and confirm any expected record/state change in the app.
3. Continue through each subsequent step, verifying both UI and side effects at each stage.

**Example pattern (adapt to your own flows):** an access-request → admin-approval → invitation-email → signup flow. Submit a request logged out, confirm the admin notification email, approve as admin, confirm an invitation email is auto-sent to the requester, extract the token from the email, open the signup page with the token, and verify the email field is pre-filled and read-only, then that account creation succeeds. Use this only as an illustration of the journey-verification shape — verify whatever multi-step flows your branch actually changed.

### Shell Tips

- **Checking emails:** `curl -sk https://<mail-host>/messages` returns a JSON array.
- **Reading email body:** `curl -sk https://<mail-host>/messages/<ID>.plain`
- **Clearing emails:** `curl -sk -X DELETE https://<mail-host>/messages`
- **Listing emails compactly:**
  ```bash
  curl -sk https://<mail-host>/messages | python3 -c "import json,sys; [print(m['id'],m['subject'],m['recipients']) for m in json.load(sys.stdin)]"
  ```
- **Running Rails code in the container** (use a heredoc for shell safety):
  ```bash
  cat > /tmp/script.rb <<'RUBY'
  user = User.find_by(email: "test@example.com")
  user.save!
  RUBY
  docker exec -i <app-container> bin/rails runner - < /tmp/script.rb
  ```
- **Looking up a record ID for a URL:**
  ```bash
  docker exec <app-container> bin/rails runner "puts Model.first.id" 2>&1 | tail -1
  ```

## Bullet N+1 Query Audit

If the project includes the `bullet` gem, it surfaces N+1 queries, unused eager loading, and counter cache opportunities in development. **Every page you visit during this review must be checked for Bullet alerts** — any "USE eager loading" alert is a defect that blocks merge.

Read `references/bullet_audit.md` for the per-page check commands, alert classification (USE / AVOID / Counter Cache), common fixes, and the reporting format.

## Handling Failures

If any page shows an error:
1. Read the error message from the screenshot.
2. Identify the root cause.
3. Fix the code.
4. Re-run `bundle exec rake` to ensure tests pass.
5. Commit the fix.
6. Restart the app with `bin/cli app restart`.
7. Re-verify the failing page.

If a multi-step journey fails silently:
1. Check the Rails logs: `docker logs <app-container> --tail 50`
2. Check whether the event was emitted and the subscriber dispatched the job.
3. Check whether the mailer was called (look for the email in MailCatcher).
4. Fix the gap in the event/subscriber/job chain.

## PWA Verification

This app is a PWA. Buttons (`button_to` forms) use POST/PATCH/DELETE and behave differently than links — the service worker must not intercept them. **A page that renders correctly does NOT mean its buttons work.**

For any PR that touches service workers, JavaScript, Turbo, form/button behaviour, or the PWA manifest, read `references/pwa_verification.md` before finishing the review. It has the full button test matrix, service worker health checks, and manifest verification commands. For backend-only PRs that don't touch UI or JS, a quick sanity click on one button is usually enough.

## Mobile Viewport Verification

The app is a PWA used on mobile devices. Buttons and links that work on desktop frequently fail on mobile due to touch targets, overflow, or viewport issues. **Test at mobile width (393x852) for every interactive element in any UI-touching PR.**

Read `references/mobile_verification.md` for the full mobile test matrix, viewport setup, mobile button tests, overflow detection commands, and the mobile-specific defect patterns. Skip only for pure backend/data PRs that don't render any new UI.

## Checklist

Report results using this template. Replace the `<...>` placeholders with the concrete surfaces your branch changed; add or remove rows as needed.

```
## Product Review Results

### Infrastructure
- [ ] App rebuild succeeds
- [ ] App restart health check passes
- [ ] Mail service running

### Desktop Pages
- [ ] Home / landing page (logged out) renders correctly
- [ ] Login via email auth works (<seed-user-email>)
- [ ] Home / landing page (logged in) renders correctly
- [ ] <index page> renders with all expected items
- [ ] <show page> renders (associated content, action buttons)
- [ ] <admin page> renders and is gated to admin role
- [ ] Each changed surface renders for every relevant role (logged out / logged in / admin / non-admin)
- [ ] Dark mode toggle works on changed surfaces
- [ ] No runtime errors on any page
- [ ] No Bullet N+1 alerts on any page (if bullet gem present)

### User Journeys
- [ ] <each multi-step flow changed by this branch> works end to end, including downstream effects (emails/jobs/state changes)

### PWA & Buttons (Desktop)
- [ ] Each changed button works (POST/PATCH/DELETE behaves correctly)
- [ ] Sign out button works
- [ ] Service worker skips non-GET requests
- [ ] No stale caches blocking functionality

### Mobile (393x852 viewport)
- [ ] No horizontal overflow on any page
- [ ] Sidebar collapses and hamburger menu works
- [ ] <changed page> buttons tappable (>= 44px touch target)
- [ ] Forms usable (input visible, submit tappable)
- [ ] <index page> cards stack properly
- [ ] Images/media scale to viewport
- [ ] Dark mode toggle accessible on mobile
- [ ] Navigation links work from mobile sidebar
- [ ] Sign out works on mobile
```
