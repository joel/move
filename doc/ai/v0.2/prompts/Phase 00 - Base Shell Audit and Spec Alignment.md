# Phase 00 - Base Shell Audit and Spec Alignment

## Goal

Confirm the generated Rails shell is operational, document what foundation pieces already exist, and align only the missing pieces required by the Move v0.2 specs.

This is an audit and alignment phase. Do not rebuild working authentication, CI/CD, deploy, or app-template infrastructure.

## Depends on

None. This is the first phase.

## Out of scope

- Move domain models.
- Organization tenancy implementation unless the shell already contains partial work that needs documentation.
- Recognition, search, MCP tools, QR, labels, or manifests.
- Visual redesign.

## Required reading

- `docs/Move - Design Specification v0.2.md`
- `docs/Move - Domain Specification v0.2.md`
- `docs/Move - Technical Foundation Specification v0.2.md`
- `docs/Move - Workflow Specification v0.2.md`
- `prompts/Phase Index.md`

## Main tasks

0. Verify the shell has Rails I18n locale loading, default English YAML files, and a convention for adding customer/UI-facing strings.
1. Create GitHub issue for Phase 00.
2. Run the shell locally.
3. Confirm deployment workflow and CI workflow are present.
4. Confirm authentication works.
5. Confirm PostgreSQL, UUID strategy, Active Storage, jobs, and test/lint commands.
6. Confirm whether ActionPolicy, Dry::Monads actions, Rails.event subscribers, audit logs, Discard, Logidze, PWA shell, and MCP harness already exist.
7. Identify deltas required by later phases.
8. Add or update documentation in the repository with the audit results.
9. Add a small smoke test if the shell lacks one.

## Audit checklist

Record each item as present, missing, partial, or intentionally deferred.

- PostgreSQL configured for app, queue, cache, and cable databases.
- UUID v7 defaults configured or fallback documented.
- Rodauth passwordless authentication.
- Invitation flow.
- Passkey login.
- Optional Google OAuth path.
- ActionPolicy installed.
- Mandatory relation scoping pattern available.
- Dry::Monads action layer.
- Rails.event subscribers.
- Append-only audit log.
- Notification center.
- Web Push, if included by shell.
- Discard soft delete.
- Logidze versioning.
- Cascade restore support, likely missing.
- Active Storage and S3-compatible storage.
- PWA shell and service worker.
- MCP harness.
- `bin/cli` local stack.
- CI commands.
- Deploy workflow.
- RSpec and FactoryBot.
- System tests.
- RuboCop, erb_lint, Brakeman, bundler-audit.
- Packwerk, if expected by the shell.

## Deliverables

- `docs/foundation-audit.md` or equivalent.
- Updated setup notes if local boot differs from the specs.
- Failing/missing foundation items converted into explicit future tasks or notes.
- No speculative rewrites of working foundation code.

## Tests and verification

Run the shell's standard checks:

```bash
bundle exec rake project:lint
bundle exec rake project:tests
bundle exec rake project:system-tests
bin/brakeman
bundle exec bundler-audit check --update
```

Runtime verification:

- App boots locally.
- Home renders logged out and logged in.
- Authentication works through the shell's supported path.
- CI command list is documented.
- Deploy workflow exists and is not modified unless broken.

## Acceptance criteria

- Audit document exists and is committed.
- The team can see exactly what the shell provides and what later phases must implement.
- No working foundation capability was rebuilt unnecessarily.
- PR includes verification notes.

## Suggested issue title

`Phase 00: Audit generated shell and align foundation plan`

## Suggested branch

`docs/phase-00-shell-audit`
