# frozen_string_literal: true

# Base class for all business-logic actions. Actions own domain operations so
# controllers stay thin and models stay persistence-focused.
#
# Includes Dry::Monads result/do notation:
#   - Success(value) / Failure(value) wrap outcomes
#   - `yield` unwraps a Success or short-circuits on Failure (railway pattern)
#
# Convention: app/actions/<domain>/<verb>.rb defines Domain::Verb < BaseAction
# with a single `call(named:, args:)` that chains `persist` + `emit_event` steps
# and returns Success/Failure. Controllers pattern-match on the result.
# See app/actions/AGENTS.md.
class BaseAction
  # Dynamic include (RBS can't model the module `Dry::Monads.[]` builds); the
  # Success/Failure surface it provides is declared in sig/dry_monads.rbs.
  # @rbs skip
  include Dry::Monads[:result, :do]

  # The row-lock mode for a PARENT row (a Box, a cascade root) taken before
  # writing its children (#757 Codex R1-R8). FOR NO KEY UPDATE still excludes
  # every other parent-first locker (it conflicts with itself and FOR UPDATE),
  # but, unlike FOR UPDATE, it does not block the FOR KEY SHARE a concurrent
  # child write's FK check takes on the parent (re-boxing an item, attaching
  # a generated image's media). With FOR UPDATE, a job holding a child row
  # while inserting an FK to the parent deadlocks against us. None of these
  # lockers changes the parent's key, so NO KEY UPDATE is sufficient.
  # Exception: Boxes::CompleteIfEmpty keeps FOR UPDATE, because its emptiness
  # check must exclude children ARRIVING (see there).
  PARENT_ROW_LOCK = "FOR NO KEY UPDATE"

  private

  # BaseAction is domain-free on purpose (#443): the archived-Move guard
  # (`ensure_writable`) is the MoveWritable mixin, included by the actions that
  # mutate a Move's contents.

  # Attributes the Logidze version(s) created while `block` runs to `actor`
  # (Technical Foundation §7.4) — stored in the version meta as `_r`, so the
  # activity feed (PR3) can show who made an edit and offer an attributed revert.
  # Returns the block's value (so callers `yield with_responsible(actor) { persist(...) }`).
  # A nil actor (system/MCP/jobs without a user) records an unattributed change.
  #
  # `transactional: false` is deliberate: the default opens its own transaction,
  # which would demote an action's `ActiveRecord::Base.transaction` to a *joined*
  # one — so a `RecordInvalid` that persist rescues internally would let the outer
  # transaction COMMIT partial writes (e.g. an orphan room on a failed box edit).
  # The non-transactional path sets the responsible via a session GUC (reset in an
  # ensure) without a transaction, so each action keeps its own rollback boundary.

  #: [T] (untyped actor) { () -> T } -> T
  def with_responsible(actor, &)
    Logidze.with_responsible(actor&.id, transactional: false, &)
  end
end
