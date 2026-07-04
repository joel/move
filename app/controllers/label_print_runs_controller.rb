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

  #: () -> untyped
  def show
    render Views::LabelPrintRuns::Show.new(move: @move, run: @run)
  end

  # POST /moves/:move_id/label_print/runs

  #: () -> untyped
  def create
    result = LabelPrintRuns::Start.new.call(
      move: @move, from: param_int(:from), to: param_int(:to),
      host: request.host_with_port, protocol: request.protocol,
      confirmed: ActiveModel::Type::Boolean.new.cast(params[:confirmed])
    )

    case result
    in Dry::Monads::Success(run)
      redirect_to move_label_print_run_path(@move, run)
    in Dry::Monads::Failure(payload) if payload.is_a?(Hash)
      # A large batch needs an explicit "print anyway" — re-render the form in its
      # confirm state. Status 422 (not 200) so Turbo renders the response: Turbo
      # Drive ignores a non-redirect 200 on a form submit and the prompt never shows
      # (the error path relies on the same 422). Hash payload carries the counts.
      render label_print_form(confirm: payload), status: :unprocessable_content
    in Dry::Monads::Failure(reason)
      render label_print_form(error: range_error(reason)), status: :unprocessable_content
    end
  end

  # GET /moves/:move_id/label_print/runs/:id/download

  #: () -> untyped
  def download
    return redirect_to move_label_print_run_path(@move, @run) unless @run.ready?

    send_data @run.document.download, filename: filename(@run),
                                      type: "application/pdf", disposition: "attachment"
  end

  private

  #: () -> untyped
  def authorize_read!
    authorize! @move, to: :show?, with: MovePolicy
  end

  #: () -> untyped
  def set_run
    @run = @move.label_print_runs.find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # :too_many's max is the effective box cap for this Move's labels_per_box (#312) —
  # at 10 copies the real limit is 40 boxes, not 200. The cap policy lives in the
  # action layer (LabelPrintRuns::Start.box_cap); the controller only consumes it.
  # Other reasons ignore the unused :max interpolation.

  #: (untyped reason) -> untyped
  def range_error(reason)
    t("label_print.errors.#{reason}", max: LabelPrintRuns::Start.box_cap(@move.labels_per_box))
  end

  #: (untyped run) -> String
  def filename(run)
    "boxes-#{format("%03d", run.from_number)}-#{format("%03d", run.to_number)}-labels.pdf"
  end
end
