# Local HTTPS edge (move-dns + move-router)

Move owns its local edge: its own DNS server and its own HTTPS router, both on
the loopback IP **127.0.0.2**. This is the ISMS CLI V2 approach (#828). It
replaces the old shared Traefik (Docker-label provider) and the whole-`.docker`
DNS, which no longer exist on this machine.

Since everything lives on 127.0.0.2, Move runs next to the ISMS V2 stack (which
owns `127.0.0.1:53/443`) on standard ports, with no conflict.

![Local edge](diagrams/local-edge.svg)

The editable scene is [`diagrams/local-edge.excalidraw`](diagrams/local-edge.excalidraw).

## Request flow

```mermaid
flowchart LR
  B["Browser"] -->|"getent / NSS"| R["systemd-resolved"]
  R -->|"~move-easy.docker<br/>(DNS delegate)"| D["move-dns<br/>dnsmasq 127.0.0.2:53"]
  R -->|"~isms.docker"| I["isms-dns 127.0.0.1:53"]
  D -->|"A 127.0.0.2"| B
  B -->|"HTTPS 127.0.0.2:443"| T["move-router<br/>Traefik, file provider"]
  T -->|"move. + &lt;slug&gt;. (priority 1)"| A["move-app-dev :9292"]
  T -->|"mail."| M["mail :1080"]
  T -->|"storage."| W["seaweedfs filer :8888"]
  T -->|"bucket. + addPrefix /move"| S["seaweedfs S3 :8333"]
```

| Piece | What it does | Where |
|---|---|---|
| `move-dns` | dnsmasq answering every name under `move-easy.docker` with 127.0.0.2. No upstreams: anything outside the zone is refused, so it is never an open resolver. | `config/dns/`, `bin/cli-files/dns-cmd/` |
| Host DNS delegate | `/etc/systemd/dns-delegate.d/move-easy-docker.dns-delegate` routes only `~move-easy.docker` to move-dns (systemd 258+). The one root-only step. | `bin/cli dns bootstrap` prints it |
| `move-router` | Traefik with the **file provider only**: no Docker socket, no container labels. Config is rendered to `~/.local/state/move/router/` on every `start`, and `watch: true` applies edits live. | `bin/cli-files/router-cmd/` |
| Certificates | A per-developer root CA, **name-constrained** to `move-easy.docker`, plus an 825-day leaf for the apex and `*.move-easy.docker`. Generated with Ruby OpenSSL. The CA key never enters a container (only `certs/leaf/` is mounted). | `~/.local/state/move/certs/` |
| Trust | `bin/cli router trust` adds the CA to the per-user NSS store (`~/.pki/nssdb`, read by Chrome/Chromium/Brave). No sudo. | |

Routes live in one place, `RouterConfig#routers`. The tenant catch-all's
`priority: 1` is load-bearing: Traefik's default priority is the rule length,
and the `HostRegexp` is longer than every `Host()` rule, so without it the
catch-all would swallow `mail.`, `storage.` and `bucket.`.

## First-time setup

```bash
bin/cli services start      # dns + router first, then db, storage, app
bin/cli dns bootstrap       # prints the root-only delegate step; run it once
bin/cli router trust        # trust the dev CA for this user; restart the browser
bin/cli dns check           # container + delegate + resolution via getent
bin/cli router check        # container + certs + a live TLS handshake + trust
```

`bin/cli router certs --rotate` replaces the root CA (re-run `trust`, then
`router restart`). `router start` renews only the leaf when it nears expiry,
so the trusted CA stays put.

Overrides: `MOVE_EDGE_IP` (default `127.0.0.2`; keep `config/dns/dnsmasq.conf`
in sync), `MOVE_TRAEFIK_VERSION`, `MOVE_APP_UPSTREAM`.

## Worktrees

`bin/cli app start` serves **one** checkout in the single `move-app-dev`
container. To live-check or test another git worktree without replacing it, use
the throwaway commands. Each starts a one-off app container on the Docker
network with the chosen checkout mounted at `/rails`, and leaves `move-app-dev`
alone.

```bash
bin/cli app run  --repo fix/862-cli -- bin/rails runner 'puts Item.count'
bin/cli app test --repo fix/862-cli -- spec/actions/items
bin/cli app test --repo ../move-wt-foo        # whole unit suite (no system specs)
```

```mermaid
flowchart LR
  CLI["bin/cli app run|test --repo T"] --> RES["CheckoutResolver<br/>git worktree list of the main checkout"]
  RES -->|"path"| RUN["docker run --rm<br/>worktree → /rails"]
  MAIN["main checkout<br/>config/master.key, .env.&lt;env&gt;"] -.->|"read when the worktree lacks them"| RUN
  RUN --> DB["move-db-dev"]
  DEV["move-app-dev<br/>(main checkout, untouched)"] --> DB
```

**`--repo <target>`** (default: the main checkout, i.e. the first
`git worktree list` entry, even when `bin/cli` is run from a worktree):

- starts with `/`, `.` or `~`: a path to a checkout (must have a `Gemfile`);
- anything else: a worktree **name**, matched on branch first (slashes
  included), then on directory name. The current directory is never used
  implicitly.
- An unknown name fails before any container starts and lists the worktrees;
  an ambiguous one names the matching paths; a registered but missing
  worktree suggests `git worktree prune`.

**`app run [ENV] [--repo T] -- CMD...`** prints `Running in <path> (branch <b>)`
first, brings up the database, and exits with the command's status. stdin is
attached only when it is a TTY (`--tty` only when stdout is one too), so it
works in pipes and agent shells. `app console` / `app connect` still target the
long-lived container.

**`app test [--repo T] [-- RSPEC_ARGS...]`** runs
`bin/rails db:test:prepare && bundle exec rspec …` under `RAILS_ENV=test` in a
container named `move-app-test`, and exits with rspec's status. With no
arguments it runs the unit suite (`spec --exclude-pattern "spec/system/**/*_spec.rb"`).
All worktrees share the one `move_test` database, so runs are serialised:

- an `flock` on `<main>/tmp/bin-cli-app-test.lock` names its holder (pid,
  checkout, branch, start time); an overlapping run is refused with that
  holder. The kernel drops the lock when the holder dies.
- the fixed container name catches a leftover run:
  `docker rm -f move-app-test`.
- a plain `bundle exec rspec` inside `move-app-dev` does **not** take the lock.

**Gitignored files.** A fresh worktree has no `config/master.key` or
`.env.<env>`. They are read from the worktree when present, otherwise from the
main checkout, and are never copied into the worktree (`git status` stays
clean). A directory where one of them should be (Docker creates a missing bind
source as an empty directory) is refused with an `rmdir` hint. `tmp/` and
`log/` are pre-created as the host user.

**Gemfile.lock drift.** The container runs the gems baked into
`workeverywhere/move-app:latest`. When the worktree's `Gemfile.lock` differs
from the image's, a warning is printed; if gems changed, `bin/cli app build`
(which also changes the image the main checkout uses).

**Not covered:** serving a worktree **in the browser** next to main. That needs a
second routed app container, and host-only sessions (#280), the Apartment
subdomain elevator and the ActionCable `allowed_request_origins` all depend on
the hostname, so it needs its own design note.

## Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `platform.isms.docker` resolves to 127.0.0.2 | the delegate says `Domains=move-easy.docker` without `~`, so resolved also uses the zone as a **search suffix**: a failed lookup is retried as `platform.isms.docker.move-easy.docker` | `Domains=~move-easy.docker` (routing-only). Re-run `bin/cli dns bootstrap` |
| move-dns and isms-dns get mixed up | a `resolved.conf.d` drop-in was used: drop-ins merge into **one global** server list | use a DNS **delegate**, which is scoped to its zone |
| `docker stop move-dns` hangs | dnsmasq started with `--no-daemon` serves TCP in the main process; resolved's kept-open TCP fallback stalls SIGTERM | the image uses `--keep-in-foreground` |
| `https://mail.move-easy.docker` returns 502 just after `mail start` | mailcatcher not listening yet | retry after a second |
| `bin/cli app run --repo …` fails with `Could not find <gem>-x.y.z in locally installed gems` | the worktree's `Gemfile.lock` is ahead of the image's bundle (the drift warning says so) | `bin/cli app build`, or run against a checkout whose lock matches the image |
| `dig` works but the browser doesn't | `dig`/`nslookup` bypass NSS | check with `getent ahostsv4 <name>` (what `dns check` uses) |
| `systemctl` warns that the unit "changed on disk" during bootstrap | resolved's unit config changed | `sudo systemctl daemon-reload` before the restart |
