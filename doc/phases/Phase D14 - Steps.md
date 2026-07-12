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
| Review fixes | `28f18d9` | Internal /code-review, 8 angles: expired-pending invisible dead end (open_for scope), one-shot scoped session stash, webauthn carry, login_param prefill, localized roles, DigestedToken concern (3rd copy), role_options + open_for single sources, Steepfile coverage. Refuted with evidence: none needed beyond design notes. Accepted: two tenant switches in Accept (phase boundary), landing/action rule duplication (read vs write side), handoff-URL shape in two homes |
| Security review | `44e22e9` (amended) | /security-review: no high-confidence findings; fixed the one real residual — raw token moved off the URL path into the filtered query/form param. Accepted residual: token in mailer job args (mirrors documented Rodauth pattern) |

| Live verify | `73e30ae` | /product-review walked the full new-user journey to a working Move; caught the one bug specs can't (cross-host accept redirect needed `turbo: false` — rack_test follows redirects regardless of Turbo). Cleaned up the verify user afterward |
| Codex round 1 | `bb08c37` | 2×P2: fixed archived-Move accept refusal (Move#writable?); accepted raw-token-in-job-args (identical to documented Rodauth key pattern) |
| Codex round 2 | `657d730` | **2×P1 + P2**: consumed-link re-grant (removed member could re-add themselves — acceptance now single-shot, no writes on resume); org-destroy FK (InvalidForeignKey on account deletion — FK now ON DELETE CASCADE); Google sign-in dropped the invite token (now carried through omniauth.params) |
| Codex round 3 | `78089e6` | P2: archived-Move invite creation blocked (Create ensure_writable) — symmetric with the accept guard |
| Codex round 4 | `1d3e580` | 2×P2: archived-Move resend blocked (guard trio complete); invited-signup onboarding self-heal (verified-but-abandoned invitee no longer stranded orgless — after_login provisions when orgless and not carrying a live invite) |

## Codex loop note

Five rounds. Severity converged as the skill's stop rule predicts: round 2 held
the real P1 security bugs (re-grant, FK), rounds 3-4 were P2 follow-ons on the
same archived-Move and onboarding themes (all real, all cheap, all fixed). The
archived-Move story is now symmetric across create/accept/resend; the invited-
signup lifecycle self-heals. Every round's findings were legitimate — none
contrived — so each was fixed rather than accepted.

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
