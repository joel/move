# Phase D1 — Execution Steps (audit log)

Flight-recorder for the tenancy + Moves effort. Append-only; factual.

- **Plan:** `doc/phases/Phase D1 - App Shell and Move Context.md`
- **Issue:** [#30](https://github.com/joel/move/issues/30) — Phase D1: Apartment multi-tenancy + Moves via actions
- **Branch:** `feature/tenancy-and-moves`
- **Kanban:** In progress

## Confirmed decisions (maintainer)

1. **Apex-only login UI** at `move.workeverywhere.docker`; **session + remember cookie shared on `.workeverywhere.docker`** (env-configurable) so the session carries to org subdomains with no redirect loop. Tenant subdomains are post-auth.
2. **Auto-create a personal Organization (tenant) on account verification**; slug derived from name/email → provision tenant → redirect to `<slug>.workeverywhere.docker`.
3. **Keep verify-before-login** in all envs (prod parity).
4. **Rodauth tables schema-qualified to `public`** + `persistent_schemas: ["public"]` + `excluded_models` → auth immune to tenant switching (Rodauth shares the AR connection via sequel-activerecord_connection).
5. **Prerequisite:** app image `pg_dump` was 17.10 vs PG 18.0 server → aborts. Fix: PGDG `postgresql-client-18` in both Dockerfiles + pin `DB_IMAGES` postgresql to `postgres:18`. Both `:sql` dumps and Apartment `use_sql` cloning depend on it.

## Step log

### Prerequisite — PostgreSQL client 18

- `dockerfiles/Dockerfile-dev` + `Dockerfile-prod`: base stage now adds the PGDG apt
  repo and installs `postgresql-client-18` (was distro `postgresql-client` = 17).
  Codename derived via `/etc/os-release` so it survives base-image bumps.
- `bin/cli-files/services/helpers.rb`: `DB_IMAGES["postgresql"]` pinned
  `postgres:latest` → `postgres:18`.
- **Verified:** rebuilt image → `pg_dump (PostgreSQL) 18.4`; `pg_dump -s -n public`
  against the PG 18.0 server exits 0 (previously aborted on version mismatch). App
  boots; `/up` returns 200; Rodauth Sequel connection healthy.
- Also pinned the prod DB accessory (`config/deploy.yml`) to `postgres:18`.

### Step 1 — schema_format :sql

- `config/application.rb`: `schema_format = :sql`.
- Generated `db/structure.sql` (primary) + `db/{cache,queue,cable}_structure.sql`
  (Solid, via Rails `structure_dump` from scratch DBs); removed the `*_schema.rb`.
- **Gotcha hit:** the dev DB carried a phantom migration `20260604130001`
  (`create_organization_memberships`) from the *closed* PR #27 branch, which
  contaminated `structure.sql` (Apartment's railtie re-loaded it on migrate). Fixed
  by deleting the bad `structure.sql` and `db reset` (drop→create→migrate from repo
  files only). Clean structure.sql now matches migrations through `20260603160000`.
- Committed with `SKIP=RailsSchemaUpToDate` (format change only, schema unchanged).
- **Verified:** app boots; `/`, `/login`, `/create-account` → 200.

### Step 2 — Organization registry (public schema)

- Migrations + `Organization` (citext slug, DNS-label validation) +
  `OrganizationMembership` (role, unique per org/user). Factories + model specs.
- **Verified:** model specs green (11 examples).

### Step 3a — Move tenant tables + module rename

- **Naming clash:** the app module `Move` collided with the `Move` model. Renamed
  the app module to `MoveApp` (only ref outside UI strings; webauthn_rp_name default
  is cosmetic). Model stays `Move`.
- Migrations + `Move` (status/unit_system, `#writable?`) + `MoveMembership`. No
  cross-schema FK to users; `move_id` FK is same-schema. Factories + specs.
- **Verified:** model specs green; full unit suite 147 examples, 0 failures; app
  boots after rename; `/`, `/login` → 200.

### Step 3b — Apartment initializer + Rodauth public-qualification

- `config/initializers/apartment.rb`: excluded_models (User, Organization,
  OrganizationMembership), persistent_schemas [public], use_sql,
  `pg_exclude_clone_tables = true` (keep excluded tables out of tenant schemas),
  `pg_excluded_names = [citext]` (don't rewrite `public.citext` to a non-existent
  tenant type — caught live during tenant creation).
- `rodauth_main.rb`: every Rodauth table schema-qualified to `public`
  (`Sequel[:public][:…]`) — model-less key tables get cloned empty into tenants,
  so auth must always read public.
- Decoupled brand name (`config.x.brand_name = "Move"`) — module rename had leaked
  "MoveApp" into the nav.
- **Verified:** tenant create/switch — `users`/`organizations` NOT in tenant schema,
  `moves` present, excluded User + qualified `public.users` resolve in-tenant, move
  isolation holds. **Full auth journey live (create → verify → sign out → sign back
  in)** with Apartment active; mini-profiler SQL confirms `public.users` /
  `public.user_email_auth_keys`. Unit suite 147→ still 0 failures.

### Step 4 — Actions

- `Organizations::Create` (reserved-slug guard, owner membership, tenant provision,
  rollback on failure) + `Moves::Create` (creator → admin). Unit specs (9) green.

### Step 5–7 — Subdomain routing + shared cookie

- Custom `MoveTenantElevator` (zone-based; `.docker` isn't a public suffix so
  Apartment's Subdomain elevator can't parse it), 404 on unknown tenant.
- Session + Rodauth remember cookie shared on `config.x.cookie_domain`
  (`.workeverywhere.docker` dev / `.app` prod); `tenant_zone` per env.
- Traefik low-priority `HostRegexp` router for `<slug>.<domain>` in `app_service.rb`.
- **Verified live:** DNS `acme.…docker` → 200 with `search_path TO "acme","public"`;
  unknown subdomain → 404; **apex login session carries to `acme` subdomain (no
  redirect loop)**.

### Onboarding

- `verify_account_view` provisions a personal Organization after the verify
  transaction; redirects to `<slug>.<zone>`. Logins route to the user's org
  subdomain.
- **Verified live:** signup `onboard1@example.com` → verify link → tenant schema
  `onboard1` created, owner membership set, redirected + logged in on the subdomain.

### Step 8 — A1 Move screens

- `resources :moves` (index/new/create); subdomain root redirects to the Move list.
  `MovesController` requires a tenant (404 on apex), authorizes via `MovePolicy`,
  creates via `Moves::Create`. `MoveCard` (status, name, progress hint, box/pending
  counts — box metrics are D2), `MoveForm` (spec fields), empty state, archived
  read-only. All copy via `moves.*` I18n. Fixed `top_nav` brand leak.
- **Bug caught live:** Phlex views lack the `t` helper → switched to `I18n.t`.
- **Verified live** (logged in on `acme`): list shows the move card; create form has
  the exact spec fields; submitting creates the move (creator → admin) and returns to
  the list; `emptyco` shows the empty state; tenant isolation holds; nav reads "Move".
- Request specs (6) cover list/empty/form/create/validation/404.

### Validation (pre-PR)

RuboCop, erb_lint clean; Brakeman 0 warnings; bundle-audit clean; **162 unit + 8
system specs, 0 failures**.
