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

  # Whether the current user may mutate the Move's content — the admin/contributor
  # (editor) tier. Viewers are read-only; non-members never reach here (set_move
  # 404s them first).
  def move_editor?
    @move&.membership_for(current_user)&.can_edit? || false
  end

  # Refuse a mutation by a non-editor (a viewer) with 403. Subclasses'
  # require_writable_move! call this before applying the archived (read-only)
  # redirect: `return deny_move_mutation! unless move_editor?`.
  def deny_move_mutation!
    respond_to do |format|
      format.html { render Views::Shared::Forbidden.new, status: :forbidden }
      format.any { head :forbidden }
    end
  end
end
