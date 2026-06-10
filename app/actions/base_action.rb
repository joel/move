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
end
