# Phase 11 - Product Hardening and Release Readiness

## Goal

Harden the full Product Phase 1 journey for production release.

By the end of this phase, the app has end-to-end system coverage, runtime journey verification, security checks, performance sanity checks, and release-ready documentation.

## Depends on

- Phase 10 complete.

## Out of scope

- New product features.
- Offline mutation queues.
- Video recognition.
- Value/insurance fields.
- Crop/bounding-box features.
- Bulk confirm.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Review all v0.2 specs and confirm implementation alignment.
2. Add missing system tests for the full user journey.
3. Add seed/demo data for local verification.
4. Harden authorization and relation scopes.
5. Review direct blob/media access for authorization leaks.
6. Review QR and manifest leakage paths.
7. Review MCP token storage, revocation, and audit behavior.
8. Review recognition failure/retry behavior.
9. Review search indexing jobs and fallback.
10. Review cascade restore behavior.
11. Add performance sanity checks for search, box lists, item lists, and summary.
12. Add admin/contributor/viewer visual verification pass.
13. Add production environment variable checklist.
14. Add README or operator notes for recognition/search providers.
15. Audit customer/UI-facing strings and move any hard-coded copy into YAML I18n files.
15. Run full pre-commit and runtime verification suite.
16. Fix only release-blocking bugs. Defer new ideas.

## End-to-end journeys to test

### Journey 1 - Account and Move

- Create Organization through subdomain/account flow.
- Create Move.
- Add contributor and viewer.
- Verify role permissions.

### Journey 2 - Pack and recognize

- Create vocabularies.
- Create box.
- Upload image.
- Recognition runs.
- Review suggestion.
- Correct one suggestion.
- Mark one false detection.

### Journey 3 - Search and locate

- Search exact term.
- Search fuzzy misspelling.
- Search semantic synonym.
- Open item detail.
- Navigate to box.

### Journey 4 - Labels and unpacking

- Generate exterior label.
- Confirm no contents on label.
- Scan QR as authenticated member.
- Generate manifest with warning.
- Mark item removed.
- Mark box unpacked.

### Journey 5 - MCP

- Create token.
- Search items through MCP.
- Add item through MCP.
- Move item through MCP.
- Revoke token and verify denial.

### Journey 6 - Restore

- Delete box with items.
- Restore box.
- Confirm cascade-restored items return.
- Confirm independently deleted child does not return.

## Security review checklist

- Cross-subdomain and cross-org access.
- MoveMembership role enforcement.
- Archived read-only behavior.
- QR token access.
- Manifest access.
- Active Storage authorization.
- MCP token digest and revocation.
- No raw provider response exposure.
- No public content listings.

## Performance sanity checks

- Boxes home with many boxes.
- Box detail with many items.
- Search with many items.
- Summary with many boxes and missing dimensions.
- Recognition job failure does not block web request.

## Tests

Run full suite:

```bash
bundle exec rake project:fix-lint
bundle exec rake project:lint
bundle exec rake project:tests
bundle exec rake project:system-tests
bin/brakeman
bundle exec bundler-audit check --update
```

Add missing tests rather than documenting fragile manual workarounds.

## Runtime verification

Perform the full checklist from Workflow v0.2.

Record:

- local subdomains used;
- users/roles tested;
- recognition provider mode used;
- embedding provider mode used;
- MCP calls tested;
- any deferred non-blockers.

## Acceptance criteria

- Product Phase 1 journey works end to end.
- Specs and implementation do not contradict each other.
- CI and runtime verification are green.
- Production configuration checklist exists.
- Known non-blockers are documented as follow-up issues.

## Suggested issue title

`Phase 11: Harden Product Phase 1 for release`

## Suggested branch

`feature/phase-11-release-hardening`
