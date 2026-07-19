# frozen_string_literal: true

# #702 — insurance claim-dossier runs. `create` starts the background generation
# (InsuranceDossierRuns::Start) and redirects to `show`, the live progress page
# that streams the bar and, when ready, the Download; `download` serves the
# finished PDF. The dossier reveals which box holds each item (with photos), so
# every action is admin-gated (MovePolicy#export_insurance_dossier?) — unlike
# the sanitized declaration. Generating is still a read-only intent, allowed on
# an archived Move.
class InsuranceDossierRunsController < MoveScopedController
  before_action { Current.nav_section = :menu }
  before_action :authorize_dossier!
  before_action :set_run, only: %i[show download]

  # GET /moves/:move_id/insurance/dossier/runs/:id

  #: () -> untyped
  def show
    render Views::InsuranceDossierRuns::Show.new(move: @move, run: @run)
  end

  # POST /moves/:move_id/insurance/dossier/runs

  #: () -> untyped
  def create
    case InsuranceDossierRuns::Start.new.call(move: @move, actor: current_user)
    in Dry::Monads::Success(run)
      redirect_to move_insurance_dossier_run_path(@move, run)
    in Dry::Monads::Failure(reason)
      redirect_to move_insurance_path(@move),
                  alert: t("insurance.errors.#{reason}", max: InsuranceDossierRuns::Start::MAX_ITEMS)
    end
  end

  # GET /moves/:move_id/insurance/dossier/runs/:id/download

  #: () -> untyped
  def download
    return redirect_to move_insurance_dossier_run_path(@move, @run) unless @run.ready?

    send_data @run.document.download, filename: "insurance-claim-dossier.pdf",
                                      type: "application/pdf", disposition: "attachment"
  end

  private

  #: () -> untyped
  def authorize_dossier!
    authorize! @move, to: :export_insurance_dossier?, with: MovePolicy
  end

  #: () -> untyped
  def set_run
    @run = @move.insurance_dossier_runs.find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
