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
  # Pack-by-pack growth (doc/project/type-checking.md roadmap): one `check` line
  # per annotated pack, in the SAME target — a second target crashes, see above.
  check "packs/labels/app/actions", inline: true

  signature "sig"

  # Diagnostics run on Steep's default preset (configure_code_diagnostics
  # defaults to Ruby.default when omitted); the blocking threshold is the
  # --severity-level=error flag at the invocation sites (CI + overcommit hook).
end
