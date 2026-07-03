# frozen_string_literal: true

# Static type checking — RBS + Steep. See doc/project/type-checking.md.
#
# Scope: the actions layer (AGENTS.md §1 rule 2) — packs' actions are staged in
# later PRs, pack-by-pack, mirroring how Packwerk boundaries were adopted.
#
# Annotations are INLINE (`#:` / `@rbs` comments in the .rb files, read natively
# by Steep 2.0's `inline: true` — no generated .rbs tree to drift). The only
# committed signatures under sig/ are hand-written shims for gems with no
# community RBS (dry-monads).
#
# ONE target on purpose. Steep 2.0.0's inline mode registers every inline source
# file globally; a file reachable from two targets (even `ignore`d in one)
# crashes the master with "Source already exists" and deadlocks the run — so the
# two-target typed/untyped ratchet pattern is not usable with inline mode yet.
# The ratchet is unnecessary anyway: an unannotated method types as
# `(?) -> untyped` (checked loosely), so files tighten one by one as they gain
# annotations, while `steep check --severity-level=error` keeps the noise from
# unknown app/Rails constants (warnings/hints) non-blocking.

target :actions do
  check "app/actions", inline: true
  # Every pack's actions (doc/project/type-checking.md roadmap, completed #519):
  # one `check` line per pack, all in the SAME target — a second target crashes,
  # see above. A NEW pack must add its line here + annotate from day one (the
  # fitness spec's packs/* glob will fail it otherwise).
  check "packs/accounts/app/actions", inline: true
  check "packs/captures/app/actions", inline: true
  check "packs/demo_data/app/actions", inline: true
  check "packs/labels/app/actions", inline: true
  check "packs/manifests/app/actions", inline: true
  check "packs/move_integration_tokens/app/actions", inline: true
  check "packs/move_memberships/app/actions", inline: true
  check "packs/organizations/app/actions", inline: true
  check "packs/photos/app/actions", inline: true
  check "packs/qr/app/actions", inline: true
  check "packs/reviews/app/actions", inline: true
  check "packs/search/app/actions", inline: true
  check "packs/session_handoffs/app/actions", inline: true
  check "packs/terms/app/actions", inline: true
  check "packs/vocabularies/app/actions", inline: true

  signature "sig"

  # Diagnostics run on Steep's default preset (configure_code_diagnostics
  # defaults to Ruby.default when omitted); the blocking threshold is the
  # --severity-level=error flag at the invocation sites (CI + overcommit hook).
end
