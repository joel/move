# frozen_string_literal: true

# E1 — bulk label-print runs (#303). `create` validates the range and starts a
# background generation job (LabelPrintRuns::Start), then redirects to `show` — the
# live progress page that streams the bar and, when ready, the Download. `download`
# serves the finished PDF. Generating labels is a read-only intent (it only reads
# boxes), so any Move member may do it — even on an archived Move.
class LabelPrintRunsController < MoveScopedController
  include LabelPrintForm

  before_action { Current.nav_section = :menu }
  before_action :authorize_read!
  before_action :set_run, only: %i[show download]

  # GET /moves/:move_id/label_print/runs/:id
  def show
    render Views::LabelPrintRuns::Show.new(move: @move, run: @run)
  end

  # POST /moves/:move_id/label_print/runs
  def create
    result = LabelPrintRuns::Start.new.call(
      move: @move, from: param_int(:from), to: param_int(:to),
      host: request.host_with_port, protocol: request.protocol
    )

    case result
    in Dry::Monads::Success(run)
      redirect_to move_label_print_run_path(@move, run)
    in Dry::Monads::Failure(reason)
      render label_print_form(error: range_error(reason)), status: :unprocessable_content
    end
  end

  # GET /moves/:move_id/label_print/runs/:id/download
  def download
    return redirect_to move_label_print_run_path(@move, @run) unless @run.ready?

    send_data @run.document.download, filename: filename(@run),
                                      type: "application/pdf", disposition: "attachment"
  end

  private

  def authorize_read!
    authorize! @move, to: :show?, with: MovePolicy
  end

  def set_run
    @run = @move.label_print_runs.find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def range_error(reason)
    t("label_print.errors.#{reason}", max: LabelPrintRun::MAX_LABELS)
  end

  def filename(run)
    "boxes-#{format("%03d", run.from_number)}-#{format("%03d", run.to_number)}-labels.pdf"
  end
end
