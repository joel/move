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
end
