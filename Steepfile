# frozen_string_literal: true

# Static type checking — RBS + Steep. See doc/project/type-checking.md.
#
# Scope: the whole actions layer (root + every pack), the models, and the
# controllers — grown layer-by-layer (#515 → #517 → #519 → #521 → #523),
# mirroring how Packwerk boundaries were adopted.
#
# Annotations are INLINE (`#:` / `@rbs` comments in the .rb files, read natively
# by Steep 2.0's `inline: true` — no generated .rbs tree to drift). sig/ holds
# hand-written shims (gems with no community RBS, community-sig gaps, def-self
# declarations) and the rbs_rails-generated model + route-helper signatures.
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
  # Controllers (#523): enumerated as FILES to exclude concerns/ — the four
  # controller concerns have `included do` bodies and instance methods calling
  # controller API on module-self, both unmodellable (see the packs/utility
  # note below; the inline parser also rejects `@rbs module-self`). Their
  # modules + the surface controllers call are declared in sig/concerns.rbs.
  check "app/controllers/accounts_controller.rb", inline: true
  check "app/controllers/activities_controller.rb", inline: true
  check "app/controllers/agreements_controller.rb", inline: true
  check "app/controllers/application_controller.rb", inline: true
  check "app/controllers/box_steps_controller.rb", inline: true
  check "app/controllers/boxes_controller.rb", inline: true
  check "app/controllers/captures_controller.rb", inline: true
  check "app/controllers/csp_reports_controller.rb", inline: true
  check "app/controllers/galleries_controller.rb", inline: true
  check "app/controllers/google_one_tap_sessions_controller.rb", inline: true
  check "app/controllers/integration_tokens_controller.rb", inline: true
  check "app/controllers/items_controller.rb", inline: true
  check "app/controllers/label_print_runs_controller.rb", inline: true
  check "app/controllers/label_prints_controller.rb", inline: true
  check "app/controllers/labels_controller.rb", inline: true
  check "app/controllers/manifests_controller.rb", inline: true
  check "app/controllers/mcp_controller.rb", inline: true
  check "app/controllers/mcp_uploads_controller.rb", inline: true
  check "app/controllers/members_controller.rb", inline: true
  check "app/controllers/menu_controller.rb", inline: true
  check "app/controllers/move_scoped_controller.rb", inline: true
  check "app/controllers/moves_controller.rb", inline: true
  check "app/controllers/recoveries_controller.rb", inline: true
  check "app/controllers/reviews_controller.rb", inline: true
  check "app/controllers/rodauth_controller.rb", inline: true
  check "app/controllers/scans_controller.rb", inline: true
  check "app/controllers/searches_controller.rb", inline: true
  check "app/controllers/session_handoffs_controller.rb", inline: true
  check "app/controllers/settings_controller.rb", inline: true
  check "app/controllers/style_guide_controller.rb", inline: true
  check "app/controllers/summaries_controller.rb", inline: true
  check "app/controllers/tenant_controller.rb", inline: true
  check "app/controllers/test_sessions_controller.rb", inline: true
  check "app/controllers/unpacking_controller.rb", inline: true
  check "app/controllers/vocabularies_controller.rb", inline: true
  check "app/controllers/welcome_controller.rb", inline: true
  # Models (#521): root + every pack's public/private models. Their
  # schema-derived signatures are GENERATED into sig/rbs_rails/ by
  # `bin/rails rbs_rails:all` (freshness-checked in CI); the inline annotations
  # below cover the hand-written methods on top.
  check "app/models", inline: true
  check "packs/activity/app/models", inline: true
  check "packs/activity/app/public", inline: true
  check "packs/captures/app/public", inline: true
  check "packs/labels/app/public", inline: true
  check "packs/move_integration_tokens/app/public", inline: true
  check "packs/move_memberships/app/public", inline: true
  check "packs/organizations/app/public", inline: true
  check "packs/search/app/public", inline: true
  check "packs/session_handoffs/app/public", inline: true
  check "packs/terms/app/public", inline: true
  # packs/utility models are enumerated as FILES on purpose: the concerns/
  # subdirectory must stay unchecked (Rails concern `included do` DSL bodies run
  # in the includer's context at runtime — Steep checks them against the
  # concern's own bare module, so every AR macro/scope call inside is a false
  # NoMethod; unmodellable today, like dry-monads' do-notation yield), and
  # `ignore` does NOT exclude inline-mode sources (Steep 2.0.0), so a directory
  # `check` can't be carved down after the fact.
  check "packs/utility/app/models/application_record.rb", inline: true
  check "packs/utility/app/models/current.rb", inline: true
  check "packs/vocabularies/app/public", inline: true
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

  # Stdlib signatures the checked scope needs beyond RBS core.
  library "cgi"

  # Diagnostics run on Steep's default preset (configure_code_diagnostics
  # defaults to Ruby.default when omitted); the blocking threshold is the
  # --severity-level=error flag at the invocation sites (CI + overcommit hook).
end
