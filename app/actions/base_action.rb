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
  include Dry::Monads[:result, :do]

  private

  # The archived-Move invariant lives here, in one place, instead of being
  # re-checked by every controller and MCP tool: a user-facing mutating action
  # calls `yield ensure_writable(move)` as its first step. An archived Move is
  # read-only (Move#writable?). Returns Failure(:move_archived) — controllers map
  # it to the friendly read-only redirect, MCP tools to a read-only tool error.
  # Reads and token revocation are not guarded (they stay allowed when archived).
  def ensure_writable(move)
    return Failure(:move_archived) unless move.writable?

    Success()
  end

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
  def with_responsible(actor, &)
    Logidze.with_responsible(actor&.id, transactional: false, &)
  end
end
