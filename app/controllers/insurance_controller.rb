# frozen_string_literal: true

# #702 — the Insurance hub: one page explaining the two exports and their
# deliberately different information design (the sanitized declaration vs the
# private claim dossier). Any member reaches the hub and the declaration; the
# dossier card renders only for Move admins (no dead-end 403, the Menu-hub
# convention).
class InsuranceController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # GET /moves/:move_id/insurance

  #: () -> untyped
  def show
    authorize! @move, to: :export_insurance_declaration?, with: MovePolicy
    render Views::Insurance::Show.new(
      move: @move,
      dossier_allowed: allowed_to?(:export_insurance_dossier?, @move, with: MovePolicy),
      item_count: @move.items.in_box.count
    )
  end
end
