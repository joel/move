# frozen_string_literal: true

# Base for the in-app surfaces nested under /moves/:move_id — Boxes, Items,
# Captures, Review, Vocabularies. Adds the responsive app shell and resolves the
# authorized Move from the route. Subclasses add their own record loaders
# (set_box / set_item / …) and writable-Move guards; the parent before_actions
# (auth, tenant, then set_move) run first, so @move is available to them.
class MoveScopedController < TenantController
  layout -> { Views::Layouts::AppShellLayout }

  before_action :set_move

  private

  def set_move
    @move = Current.move = authorized_scope(Move.all).find(params.expect(:move_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Authorize that the current user holds an editing role (admin/contributor) on
  # the Move — the authorization decision lives in MovePolicy#edit_contents?, so a
  # viewer is refused with the standard ActionPolicy 403. Subclasses'
  # require_writable_move! call this before applying the archived (read-only)
  # redirect, which is a separate UX concern (a writable check, not authorization).
  def authorize_move_mutation!
    authorize! @move, to: :edit_contents?, with: MovePolicy
  end

  # Whether the current user may mutate this Move's contents *now*: an editing
  # role (admin/contributor) on a writable (non-archived) Move. Surfaces pass
  # this to their views as `editable:` so mutating affordances are hidden from
  # viewers and on archived Moves — the UX complement to the server-side 403
  # (the boundary is already enforced; this just stops showing dead controls).
  # Mirrors MoveMembershipAuthorization#editor_of?.
  def editable_move?
    @move.writable? && allowed_to?(:edit_contents?, @move, with: MovePolicy)
  end
end
