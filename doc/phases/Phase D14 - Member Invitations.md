# Phase D14 — Member Invitations

**Release tag:** `v0.X.0-invitations` (next free minor at execution time)
**Branch:** `feature/member-invitations`
**Design status:** ⚠️ Design gap — F1 has no pending-invite/landing screens in Stitch (see §3)
**Depends on:** D11 (Members & Roles), #280 (session handoff), #369 (terms gate)
**Domain backing:** Technical Foundation §4.5 (L170-175) + §11 (`Organizations::InviteUser`, `MoveMemberships::Invite` — implemented here as `MoveInvitations::*`, see §5 note); Phase D11 §5 and its "Out of scope" (L64-66); Design Spec §4 F1.

---

## 1. Goal

Let a Move admin invite **anyone by email** — including people with no account and no
Organization membership — closing D11's explicit deferral. The invite email carries a
single-use, expiring link to the apex; accepting authenticates the invitee
(create-account or magic-link branch), creates the **OrganizationMembership before the
MoveMembership** (Design Spec F1 rule), and lands them on the Move via the existing
session handoff. Also fixes the F1 dead-end where the Invite CTA vanishes whenever the
org has no spare users (`app/components/members/header.rb` L26 `if @candidates.any?`).

## 2. Screens delivered

- **F1 — Members & roles (extended):** ungated Invite CTA, invite-by-email card,
  pending-invitations list (email · role chip · expiry · Resend · Revoke).
- **New — Invitation landing (apex):** "{Inviter} invited you to {Move} at {Org} as
  {Role}" with the auth/accept CTA (branches: signed-in-matching → Accept button;
  anonymous → create-account or sign-in links carrying the token).
- **New — Invitation unavailable (apex):** ONE generic page shared by
  invalid/expired/revoked/consumed/wrong-account (non-disclosing).

## 3. Design references

- Existing F1: `Members & Roles (Dark) - Responsive` →
  `screens/b909f3a2e65c4ae09dbf77f615e81c86`; `… - Mobile` →
  `screens/4ba298fa96a143279cad534328165807`. Dark-only — build light from
  Refined-Palette tokens.
- **Gap (do FIRST):** neither screen shows a pending-invite row, an invite-by-email
  form, or the apex landing/unavailable pages. Log `§F1-INVITES` in
  `DESIGN-DISCREPANCIES.md`, generate the screens on the canonical design system,
  record the new `screens/<id>`s there and in `README.md` §2, then build.

## 4. Content & behaviour (from spec + decisions)

- **Admin-only** (existing `MovePolicy#manage_members?`); invite = email (any
  address) + role (admin/contributor/viewer; default contributor).
- The org-candidates AddForm **stays** (instant add, still pool-gated); the new
  invite-by-email form is **always rendered** and becomes the header CTA target —
  `Members::Header` drops the `@candidates.any?` gate (the reported bug) and leaves
  `candidate_pool_streams`.
- Pending list streams via Turbo; resend **rotates token + expiry in place** (old
  link dies instantly; one pending row per (move, email) via partial unique index);
  revoke is an atomic guarded update (can never land on an accepted invite).
- **Accept binding:** the signed-in user's email must equal the invited email
  (citext). All failure modes → the one generic unavailable page (`:not_found`).
- **Journey:** apex link → landing → authenticate as invited email (hidden-field +
  email-link token carry) → `MoveInvitations::Accept`: validate (incl. Move still
  exists — tenant switch — BEFORE any join) → atomic claim → idempotent org-join
  (role `member`) → `Apartment::Tenant.switch { MoveMemberships::Add }` (invited
  role) → handoff with `return_path` → terms gate intercepts naturally →
  `/moves/:id/boxes`.
- **Invited signups skip `ensure_personal_organization`** (no stray personal org for
  an invited teammate) when the request carries a valid pending invite for that
  email; falls back to provisioning otherwise. Product decision — record in Steps.
- Inviter demoted/removed later: invitation honored (revoke covers regret). Move
  archived: accept succeeds (membership ≠ write access). Move deleted: generic
  failure, **no org-join**. Org membership is never rolled back on move-join
  failure (durable prerequisite; documented).

## 5. Domain & actions required

> Naming: Technical Foundation §11 says `Organizations::InviteUser` +
> `MoveMemberships::Invite`; implemented as `MoveInvitations::*` in a dedicated
> `packs/move_invitations` to keep Packwerk acyclic (Accept must call
> `MoveMemberships::Add`, so living inside that pack would cycle). Deviation
> documented here deliberately.

**Migration 1 — `create_move_invitations` (public schema; register the model in
`config/initializers/apartment.rb` `excluded_models`):**
`organization` FK (uuid) · `move_id` uuid (tenant Move, NO FK — mirrors
`move_memberships.user_id`) · `email` citext · `role` string default
"contributor" · `invited_by_id` uuid FK users `on_delete: :nullify` ·
`token_digest` string unique (SHA-256 hex; raw never stored) · `expires_at` ·
`accepted_at` · `revoked_at` · timestamps. Partial unique index on
`[move_id, email] WHERE accepted_at IS NULL AND revoked_at IS NULL`; index on
`expires_at`. Model copies `SessionHandoffToken` (TTL = 7.days, generate/digest,
`pending?/expired?`, `scope :pending`, `scope :purgeable` = terminal > 30 days).

**Migration 2 — `add_return_path_to_session_handoff_tokens`:** nullable string;
`SessionHandoffs::Mint` gains `return_path:` kwarg, `Consume` returns it,
`SessionHandoffsController#establish_session` redirects there when it is a safe
internal path (leading `/`, not `//`), else `root_path`. Existing callers unchanged.

**Actions (`BaseAction` + Dry::Monads; `# pack_public: true`):**

| Action | Behaviour | Event |
|---|---|---|
| `MoveInvitations::Create` | validate role ∈ `MoveMembership::ROLES`; reject emails already on the Move (`:already_member` — admins see the roster, no new disclosure); persist digest + TTL; rescue `RecordNotUnique` → `:already_invited`; mail after commit | `move_invitation.created` |
| `MoveInvitations::Revoke` | atomic guarded `update_all(revoked_at:)` | `move_invitation.revoked` |
| `MoveInvitations::Resend` | rotate digest + expiry in place (guard: pending); re-mail | `move_invitation.resent` |
| `MoveInvitations::Accept` | `(raw_token:, user:)` → validate → claim → org-join → move-join → `Success({organization:, move_id:})`; re-click by the matching user after acceptance re-runs the idempotent joins (crash-resumable) | `move_invitation.accepted` (+ `move_membership.added` from the reused `Add`) |

**Activity wiring** (`packs/activity` Builder SUBJECTS → `["Move", :move_id]`,
`META_KEYS` += `:email`, `activities.en.yml` feed strings for all four events —
the silent-drop gotcha applies).

**Mailer:** `packs/move_invitations/app/mailers/move_invitation_mailer.rb` <
`ApplicationMailer` (first transactional mailer; html+text templates; i18n
subject/body; apex link; `deliver_later` after commit).

**Purge:** `PurgeStaleMoveInvitationsJob` + `config/recurring.yml` nightly entry
(`purge_stale_session_handoff_tokens` precedent; public schema, no tenant loop).

**Routes/controllers:**
- Tenant (nested under moves, next to members): `resources :invitations, only:
  %i[create destroy] do member { post :resend } end` →
  `InvitationsController < MoveScopedController`, `manage_members?` gate,
  `rate_limit to: 10, within: 1.hour, by: -> { current_user.id }`, Turbo-Stream
  responses (pending-list container + toast).
- Apex: `get/post "invitations/:token"` → `InvitationAcceptancesController`
  (`show` = landing, works anonymous; `create` = accept, requires auth; both
  `rate_limit to: 20, within: 1.minute, by: -> { request.remote_ip }`; every
  failure → the generic unavailable view). On success: mint handoff with
  `return_path`, `reset_session` (apex broker pattern), redirect to
  `https://<slug>.<zone>/session/handoff?token=…`.

**Rodauth touch-points (all verified against current code):**
1. `rodauth_main.rb`: `create_account/login/email_auth_request/email_auth`
   `*_additional_form_tags` → hidden `invite_token` (charset-validated).
2. Add the missing `*_additional_form_tags` renders to
   `app/views/rodauth/_login_form.html.erb` and `_email_auth_request_form.html.erb`
   (confirmed absent today; `create_account.rb` already renders its own).
3. Pass `invite_token` into `RodauthMailer.verify_account/email_auth` links
   (cross-device-safe carry — Rodauth clears pre-auth session state).
4. `login_redirect`/`verify_account_redirect` → `/invitations/<token>` (stay on
   apex, session intact) when a valid-charset token param is present.
5. `auth_methods.rb#ensure_personal_organization` (L167) → skip for valid pending
   invites matching the account email.
6. Degradation guarantee: any lost carry is recovered by re-clicking the invite
   link while authenticated — the flow never dead-ends.

## 6. Acceptance criteria

- [ ] Admin sees the Invite CTA with zero spare org users (the reported bug) and
      can invite any email with a role; non-admins get no UI and 403s (UI + server).
- [ ] Invite mail (Mailpit in dev) carries an apex link; only the digest is stored;
      the link is single-use.
- [ ] New-user journey end-to-end: landing → create account (email locked, token
      via hidden fields + email link) → verify → accept → **OrganizationMembership
      exists before MoveMembership** → handoff → terms gate → lands on the Move,
      with NO personal org provisioned.
- [ ] Existing-user journey via the email-auth branch; existing org member accept
      skips the org-join idempotently.
- [ ] Expired / revoked / consumed / unknown / wrong-account all show the one
      generic page, `:not_found`, non-disclosing.
- [ ] Revoke + Resend from the pending list; resend voids the old link instantly.
- [ ] Activity feed shows invited/revoked/resent/accepted + member added.
- [ ] Rate limiters WIRED (spec-asserted; thresholds untestable under :null_store);
      purge job in recurring.yml; strings I18n; seeds updated (§8 mandate:
      `pending@example.com` deterministic-token invite on the demo Move);
      RuboCop/Brakeman/Packwerk/Steep/architecture specs green.
- [ ] Existing `spec/requests/members_spec.rb` CTA-tracks-pool assertions
      consciously amended (CTA now unconditional for admins); the rest unchanged.

## 7. Runtime verification (dev, Mailpit)

As admin on `acme.move-easy.docker`: invite `newbie@example.com` (contributor) →
pending row streams in → open the mail in Mailpit → private window: landing →
create account → verify link (assert `invite_token` rides it) → accept → handoff
→ terms → `/moves/<id>/boxes`; console-confirm OrganizationMembership(role member)
+ MoveMembership(contributor) + no personal org. Then: re-click link → generic
page; wrong-account open → generic page; revoke kills a link; resend rotates it;
existing-org-user invite accepts via email-auth with move-join only; F1 renders
the CTA for an org with zero spare users. Full auth journey re-verified (§1 #3).

## 8. Out of scope

Org-level invitation admin / org-role selection (always `member`); bulk invites;
reminder emails; custom messages; localization beyond `en`; removing org
membership on move-membership removal.

## 9. Phase audit trail

_Fill on execution:_ Issue: · PR: · Verification: · Release:

---

## Appendix A — Race/edge-case table (pre-mortem, binding on implementation)

| Case | Resolution |
|---|---|
| Double-accept (two tabs / re-click) | Atomic claim; loser (matching email) falls into re-run-idempotent-joins → redirect; never user-visible error |
| Accept after revoke/expiry | Validate rejects; claim's WHERE backstops a racing revoke |
| Revoke racing accept | Both contend on guarded `update_all`; exactly one wins; revoking an accepted invite impossible by construction |
| Already org member at accept | `find_or_create_by` + rescue `RecordNotUnique` → success |
| Already move member at accept | `MoveMemberships::Add` `:already_member` → success (existing race-safe path) |
| Crash between claim and joins | Re-click resumes (accepted + matching email ⇒ idempotent joins re-run); org membership never rolled back (documented) |
| Inviter demoted/removed | Invitation honored; `invited_by_id` nullifies on user deletion; copy degrades gracefully |
| Move archived | Accept succeeds; write-access enforcement stays in policies |
| Move deleted | Validated (tenant switch) BEFORE any join → generic failure, no org-join |
| Re-invite while pending | Partial unique index → "already invited — Resend"; resend rotates in place |
| Case-variant email | citext throughout (create, uniqueness, accept binding) |
| Account deleted then accepts | Email-bound: re-register on that email and accept (if unexpired) |
| Brute force / enumeration | 256-bit token, digest-only, IP rate limit, one generic failure surface |

## Appendix B — Commit slicing (atomic; security-review-mandatory flagged)

1. Model layer: migration + `MoveInvitation` + apartment exclusion + purge job/recurring + specs *(token storage — in SR scope)*
2. Actions + events + activity wiring + action specs covering Appendix A **(SR: yes — auth/tenancy boundary)**
3. Mailer + templates + i18n + spec
4. Handoff `return_path` (+ open-redirect guard) **(SR: yes)**
5. Apex endpoints + landing/unavailable views + IP rate limit + request specs **(SR: yes — new unauthenticated endpoint)**
6. Rodauth carry (form tags + partials + mailer links + redirects + personal-org skip) **(SR: yes — auth flow)**
7. F1 UI + tenant endpoints + i18n + seeds + members_spec amendments + system spec
8. E2E system spec + docs (this phase doc's audit trail, DESIGN-DISCREPANCIES resolution, README §2 row)

Design-gap Stitch work precedes commit 7; `/security-review` runs at the Step 5c/5d gate before push.
