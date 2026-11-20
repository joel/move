# Auth layer (passwordless Rodauth)

Authentication lives here:

- `rodauth_app.rb` — the Roda middleware and the per-request route block
  (`load_memory` + the orphaned-session guard).
- `rodauth_main.rb` — the Rodauth configuration (features, tables, the custom
  `verify_account_view` auto-verify override, remember-me, OmniAuth).
- `webauthn/` — passkey name resolution helpers.

Auth is **passwordless** — passkeys (WebAuthn), one-time email links, and
optional Google OAuth, never a password.

> **Auth is fragile. Live-test the full journey in a real browser after any
> change** — create account → email verify link → auto-login → sign out → sign
> back in. A green test suite is **not** sufficient. See the Runtime Test
> Workflow in the root `AGENTS.md` / the `/product-review` skill.

## Gotchas

### 1. Stale session for a deleted account (issue #32, fixed in v0.5.1)

**Symptom.** After a local `bin/cli db reset` / reseed — or any time an account
is removed while a browser still holds its cookie — onboarding silently breaks:
the create-account → email-verify flow bounces to `/login` with *"invalid
verify account key"*, and a follow-up login POST then `403`s. Tell-tale in the
logs: a `current_user` query for a UUID that no longer exists in `users`.
Production is unaffected (real users have valid accounts), which makes it look
like a local-only "auth is broken" mystery — it cost hours before it was pinned.

**Root cause.** Rodauth's verify-account flow is two requests — it stores the
key in the session and `302`s to strip it from the URL, then reads it back:

1. `GET /verify-account?key=…` → store key in session → redirect to `/verify-account`
2. `GET /verify-account` → read key from session → verify

`load_memory` runs on every request. Finding a logged-in session whose
`account_from_session` is now `nil`, Rodauth calls `clear_session`
**mid-request**, wiping the in-flight `verify_account_key` before step 2 can
read it. An orphaned session must be treated as logged-out from the first
touch, not cleared half-way through a flow.

**Fix (in place).** A guard at the top of the `RodauthApp` route block drops an
orphaned session up front, so every flow runs against a clean, stable session:

```ruby
# app/misc/rodauth_app.rb
rodauth.clear_session if rodauth.logged_in? && rodauth.account_from_session.nil?
```

Covered by `spec/requests/stale_session_spec.rb` (the spec fails without the
guard — the dead `session_key` lingers — and passes with it).

**If you hit it as a developer:** clear cookies for the dev host (or use a
private window). The guard now does this automatically server-side, but a
browser tab opened before the fix may still carry a pre-guard cookie.

### 2. Forms lose query params on POST

Rodauth form POSTs drop query-string params (e.g. `?token=…`). Carry them
through **hidden fields** in the Phlex view, and pre-fill/lock fields the system
already knows (mismatches cause silent rejections that look like bugs). Signup
forms must carry invite tokens this way.

### 3. Verify-before-login gate

An unverified account (`status = 1`) cannot log in — Rodauth shows *"the account
you tried to login with is currently awaiting verification"*. The email verify
**link** itself verifies and auto-logins (custom `verify_account_view` in
`rodauth_main.rb`); users must click the link, not retry login.

### 4. Remember-me persistence

Remember-me (`_move_remember`, 30 days) plus `load_memory` on every request keep a
user signed in. As of #280 it is established **only on the org subdomain** (when
`SessionHandoffsController` consumes the handoff token), **not** on the apex — the
apex is a pure auth broker that clears its own session on handoff and never sets a
remember cookie. To test a clean signup you must be **fully logged out** (clear
cookies / private window) — otherwise the browser silently re-authenticates as the
remembered account.

### 5. Seed users default to status 1 (unverified)

Seeded/fixture users default to `status = 1` and therefore can't log in. Set
`status = 2` (verified/open) to make them sign-in-able. In specs, the test-only
`/test/login` route (see `TestSessionsController`) opens the account for you.

### 6. Rodauth 2.47+ account-reload check and token-in-session (#820)

**Symptom.** After bumping Rodauth past 2.47, a *signed-in* user who requests
or consumes a sign-in link (`POST /login`, `/email-auth-request`,
`/email-auth`, `/verify-account`) gets a 500:
`Rodauth::Error: account retrieved multiple times during rodauth route,
original retrieval type: session, new retrieval type: login`.

**Root cause.** Rodauth now records *how* the account was loaded in a request
and raises when the route re-loads it a different way. Several things load it
**by session** before the route's own lookup: the orphaned-session guard in
`RodauthApp` (gotcha 1), the `Current.user` before_action (`rails_account` —
rodauth-rails runs controller callbacks *inside* the route), and remember-me's
`load_memory` (deadline extension while signed in; auto-login from the cookie).
We leave `already_logged_in` unset, so signed-in users can reach those routes.

**Fix (in place).** `account_reload` in `RodauthMain` lets a session-loaded
account be re-resolved by the route (the pre-2.47 behaviour); every other
reload keeps Rodauth's default. Covered by
`spec/requests/rodauth_logged_in_routes_spec.rb` (session, remember-deadline,
and remember-auto-login contexts). Don't "fix" it by making individual loaders
stateless — `load_memory` is Rodauth's own and would still trip it.

**Also since 2.47:** non-JSON POSTs to token routes ignore a `key` form param;
the key must come from the session, set by the emailed link's GET (which then
redirects to strip it). Request specs must `get` the link and `follow_redirect!`
before `post "/email-auth"` / `"/verify-account"` — posting `key:` directly now
fails as "invalid key".
