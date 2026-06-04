# Phase 01 - Subdomain Tenancy and Organizations

## Goal

Add Organization account separation and subdomain-based tenant resolution.

By the end of this phase, users can belong to Organizations, requests resolve the current Organization from the subdomain, and cross-org reads are blocked.

## Depends on

- Phase 00 complete.

## Out of scope

- Move domain model.
- MoveMembership roles.
- Boxes/items.
- Recognition/search.
- MCP tokens.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Create `Organization` model.
2. Create `OrganizationMembership` model.
3. Add globally unique organization `slug` used as subdomain.
4. Add `Current.organization` and `Current.organization_membership`.
5. Resolve Organization from subdomain in `ApplicationController`.
6. Require OrganizationMembership after authentication for tenant routes.
7. Add account creation or onboarding path that creates Organization and makes creator account admin.
8. Add Organization invitation path if not already provided by shell.
9. Add tenant-scoped policy base helpers.
10. Add cross-org non-disclosure handling.
11. Add local dev support for wildcard subdomains.

## Data model

### organizations

- `id`
- `name`
- `slug`
- `settings`
- `created_by_user_id`
- timestamps

Indexes:

- unique `slug`

### organization_memberships

- `id`
- `organization_id`
- `user_id`
- `account_admin`, default false
- timestamps

Indexes:

- unique `(organization_id, user_id)`
- `(user_id, organization_id)`

## Authorization rules

- Account admin may manage Organization settings and Organization invitations.
- Any OrganizationMembership can access account shell pages.
- Cross-organization access returns 404 or an equivalent non-disclosing response.
- OrganizationMembership is not a Move role.

## UI routes

- Account/Organization setup.
- Organization settings.
- Invitation acceptance if needed.
- Tenant not found / access denied state.

## Tests

- User can create Organization.
- Creator becomes account admin.
- Subdomain resolves Organization.
- Authenticated user without OrganizationMembership cannot access tenant.
- User in Organization A cannot see Organization B data.
- Slug uniqueness and validation.
- Factories for Organization and OrganizationMembership.

## Runtime verification

Use at least two local subdomains:

```text
https://john.<APP>.<DOMAIN>.docker
https://acme.<APP>.<DOMAIN>.docker
```

Verify:

- logged-in user sees only their Organization;
- cross-subdomain access fails safely;
- invitation/account setup works;
- audit/notification shell paths still work if present.

## Acceptance criteria

- Organization tenancy works by subdomain.
- Base policies and Current context are tenant-aware.
- Existing auth/deploy/CI behavior remains intact.
- PR records subdomain runtime verification.

## Suggested issue title

`Phase 01: Add subdomain organizations and account tenancy`

## Suggested branch

`feature/phase-01-organizations`
