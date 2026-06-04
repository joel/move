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
