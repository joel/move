# frozen_string_literal: true

# #702 — serves the movers-facing insurance declaration PDF inline (the box
# manifest pattern: authorize → audit-evented data assembly → send_data). The
# declaration is sanitized by design (no box numbers / rooms / photos), so any
# Move member may generate it — parity with BoxPolicy#manifest?.
class InsuranceDeclarationsController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # GET /moves/:move_id/insurance/declaration

  #: () -> untyped
  def show
    authorize! @move, to: :export_insurance_declaration?, with: MovePolicy

    case InsuranceDeclarations::Generate.new.call(move: @move, actor: current_user)
    in Dry::Monads::Success(sections:, total_items:)
      pdf = InsuranceDeclarationPdf.new(move: @move, sections: sections, total_items: total_items)
      send_data pdf.render, filename: "insurance-declaration.pdf",
                            type: "application/pdf", disposition: "inline"
    in Dry::Monads::Failure(reason)
      redirect_to move_insurance_path(@move),
                  alert: t("insurance.errors.#{reason}", max: InsuranceDeclarations::Generate::MAX_LINES)
    end
  end
end
