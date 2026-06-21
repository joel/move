# frozen_string_literal: true

# F3 — Menu hub. The top-level controls hub for a Move: grouped links to the
# Organize surfaces (vocabularies, members, summary) and the App surfaces
# (settings, assistant/integrations, account), plus switch-move and sign-out.
# Read-only for any member; the links it shows are filtered to what the user may
# reach (admin-only destinations are hidden for non-admins, no dead-end 403).
# Thin: authorize (show?) → render.
class MenuController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # GET /moves/:move_id/menu
  def show
    authorize! @move, to: :show?, with: MovePolicy

    render Views::Menu::Show.new(
      move: @move,
      admin: allowed_to?(:manage_members?, @move, with: MovePolicy),
      # Bulk box steps is an editor-only surface, so the link is hidden for
      # viewers (and the controller still enforces it) — no dead-end 403. An
      # editor on an archived Move still sees it and gets the friendly read-only
      # redirect, consistent with the other editor surfaces.
      editor: allowed_to?(:edit_contents?, @move, with: MovePolicy)
    )
  end
end
