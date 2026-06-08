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
end
