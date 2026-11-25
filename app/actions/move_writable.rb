# frozen_string_literal: true

# The archived-Move invariant (#111), as a mixin for the actions that mutate a
# Move's contents. It lives here, with the Move domain, and not in BaseAction
# (#443): BaseAction stays domain-free (Dry::Monads + with_responsible), so it
# can be promoted to the packs/utility kernel. The coupling to Move is a method
# call (`move.writable?`) that Packwerk can't see; including this module makes
# it a visible constant reference instead.
#
# A user-facing mutating action includes MoveWritable and calls
# `yield ensure_writable(move)` as its first step, so the guard is checked in
# one place instead of by every controller and MCP tool. An archived Move is
# read-only (Move#writable?). Returns Failure(:move_archived): controllers map
# it to the friendly read-only redirect, MCP tools to a read-only tool error.
# Reads and token revocation are not guarded (they stay allowed when archived).
#
# The including class must provide Dry::Monads' Success/Failure (every
# BaseAction subclass does); sig/dry_monads.rbs grants them to this module for
# Steep, like Items::CurrentBoxLock.
module MoveWritable
  private

  #: (untyped move) -> (Dry::Monads::Failure[Symbol] | Dry::Monads::Success[nil])
  def ensure_writable(move)
    return Failure(:move_archived) unless move.writable?

    Success()
  end
end
