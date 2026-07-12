# Phase D14 — Member Invitations — Steps (flight recorder)

Issue: [#608](https://github.com/joel/move/issues/608) · Plan: `Phase D14 - Member Invitations.md` (user-approved in plan mode, 2026-07-12) · Branch: `feature/member-invitations`

| Step | Commit | Notes |
|------|--------|-------|
| Plan doc | `d49f16f` | Phase doc committed first (docs never at final HEAD) |
| Model layer | `d655062` | Public-schema `move_invitations` + pack + purge job + specs. Reciprocal `visible_to` on organizations/move_memberships packs |
| Actions + mailer + activity | `a0fbafd` | **Slicing deviation:** plan's commits 2+3 merged — Create/Resend without delivery would be a broken intermediate. Apex routes landed here (mailer URL helper needs them; controller follows) |
| Handoff `return_path` | `0984f40` | Open-redirect guard refuses `//` and `/\` escapes; Consume now returns `[user, return_path]` (single caller updated) |
| Apex endpoints | `17d3d93` | One generic unavailable page for all failure modes; accepted+matching keeps resolving (resume) |
| Rodauth carry | `5ccabe1` | Two wipe points found live: (a) GET-with-key handlers redirect to a clean URL dropping the query param → session stash at `before_*_route`; (b) `autologin_session`→`clear_session` wipes the stash before `login_redirect`/`ensure_personal_organization` → token also pinned as an instance memo at route entry. The exploration's "partials missing additional_form_tags renders" claim was stale — all views already render them |
| F1 UI + seeds | `ce88e45` | Header CTA ungated (the motivating bug); UX-walk decisions encoded: pending list newest-first + hidden when empty, top-insert + highlight + toast on invite, reset-form clears/refocuses (now matches email inputs), row-targeted streams for resend/revoke. Design gap logged as DESIGN-DISCREPANCIES §F1-INVITES (Stitch backfill pending) |

## Decisions recorded (beyond the phase doc)

- **Product:** invited signups skip `ensure_personal_organization` only for a live
  invitation matching the account email; anything stale falls back to the normal
  personal org (spec-asserted both ways).
- **No E2E system spec across hosts:** rack_test cannot hop apex↔tenant hosts; the
  journey is covered by the request-spec chain (tenant endpoints → mailer link →
  auth carry → apex accept → handoff `return_path`) plus live verification. The
  tenant-side UI has its own system spec.
- **No cross-host toast after acceptance** (session resets at the handoff); the
  Move page itself is the confirmation. Accepted limitation.
- **No live broadcast when an invitee accepts while the admin watches** — rare;
  the activity feed records it. Accepted limitation.

## Gotchas hit (memory-worthy)

- Rodauth's GET-with-key clean-URL redirect silently drops extra query params —
  any param that must survive the passwordless flows needs BOTH the hidden-field
  carry and a route-entry stash/memo (see `carried_invite_token`).
- This app's `verify_account` auto-verifies on GET (no confirmation form) — specs
  that expect a verify form will chase an empty 302 body.
- `login_param` is `email` here, not Rodauth's default `login` (bit the request
  specs: POSTs silently 422 with the wrong field name).
- RSpec `and_yield` DOES return the block's value (probed) — a stubbed
  `Apartment::Tenant.switch` behaves like the real one for return values.
- A lazy `let(:invitation)` + an action that looks the row up by digest = the
  composed call "fails" while every step passes in isolation. `let!` for rows the
  action must find.
