---
name: security-review
description: Use this skill after implementation is complete and before creating a PR, to perform a security and vulnerability review of the code changes. Trigger when the user says "security review", "check for vulnerabilities", "security audit", or after completing a feature that touches authentication, authorization, data handling, file uploads, API endpoints, or user input. Also trigger automatically at the end of any execution-plan phase before the PR is opened. This skill acts as an adversarial reviewer — its job is to find what the main agent missed.
---

# Security Review

Perform a targeted security audit of the changes introduced in the current branch before a PR is opened. This is an adversarial pass: assume the implementation agent was optimistic and missed edge cases.

## Project Context

- **Auth framework:** Rodauth (handles login, signup, verify, email-auth, webauthn/passkeys)
- **Authorization:** ActionPolicy (`authorize!` in controllers, `allowed_to?` in Phlex views)
- **Authorization pattern:** Controllers use `before_action :authorize_<resource>!` calling `authorize!(@record || ModelClass)`. Policies inherit from `ApplicationPolicy` which provides `superadmin?` helper.
- **Query scoping:** This project uses `<Model>.find(params[:id])` (not `current_user.<model>s.find`) — authorization is enforced by ActionPolicy, not query scoping. This is intentional. Do NOT flag unscoped `find` as a vulnerability unless the controller is also missing `authorize!`.
- **Views:** Phlex components (not ERB). Output is auto-escaped by Phlex. The only exception is `unsafe_raw` — flag any new usage of `unsafe_raw` for review.
- **UUIDs:** All primary keys are UUIDs (not sequential integers), which reduces enumeration risk but does not eliminate it.
- **Container:** `<app-container>` for dev environment

## Scope

Review only the diff introduced by the current branch:

```bash
git diff main...HEAD
```

If reviewing an already-open PR:

```bash
unset GITHUB_TOKEN && gh pr diff <PR_NUMBER>
```

## Checklist

Work through each category. Mark N/A if the category does not apply to this diff.

### Authentication & Authorization
- [ ] Are all new routes protected by `require_authenticated_user!`?
- [ ] Are authorization checks present via `authorize!` (not just authentication)?
- [ ] Do new policies correctly check roles? (superadmin via `superadmin?`, resource roles via membership/ownership lookup)
- [ ] Are invitation/token flows single-use and time-limited?
- [ ] Can a user bypass authorization by crafting a direct HTTP request (even if the UI hides the button)?

### Input & Output
- [ ] Is all user input validated and sanitized before use?
- [ ] Are strong parameters enforced on every controller action that accepts params (`params.expect` or `params.require.permit`)?
- [ ] Is output escaped correctly? (Phlex auto-escapes; flag any new `unsafe_raw`, `html_safe`, or `raw` usage)
- [ ] Are file uploads validated for type and size? (Active Storage `has_many_attached`)

### Data Exposure
- [ ] Do rendered views expose fields that should be private (e.g. password digests, tokens, internal state)?
- [ ] Are error messages generic enough to not leak internal state? (`head :forbidden` for authz, not detailed error)
- [ ] Are logs free of sensitive values (tokens, passwords, emails in plain text)?
- [ ] Does the 403 response reveal whether a resource exists? (It should not — return 403 whether the resource exists or not)

### Mass Assignment & Query Safety
- [ ] Are there any raw SQL fragments that could allow injection?
- [ ] Are policy checks applied before any mutation (create, update, destroy)?
- [ ] For nested resources (e.g. `<parent>.<children>.find`), is the parent scoped correctly?

### Secrets & Configuration
- [ ] Are no secrets, tokens, or credentials hardcoded or committed?
- [ ] Are environment variables used correctly?
- [ ] Is `.env` or credentials file excluded from the diff?

### Dependencies
- [ ] Have any new gems or packages been added? If so, note them for manual review.

## Output Format

Report findings grouped by severity:

```
## Security Review — <branch name>

### Critical (must fix before merge)
- <finding>: <file>:<line> — <explanation and fix>

### Warning (should fix or consciously accept)
- <finding>: <file>:<line> — <explanation>

### Informational (no action required)
- <observation>

### Not applicable
- <categories that don't apply and why>
```

If no issues are found, state that explicitly — a clean bill of health is a valid outcome.

## Fixing Issues

For each Critical finding, open a fix inline before the PR is created. Follow the execution-plan commit conventions. Do not batch multiple fixes into one commit.

For Warnings, ask the user whether to fix now or defer to a follow-up issue.
