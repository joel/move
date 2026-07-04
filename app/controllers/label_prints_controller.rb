# frozen_string_literal: true

# E1 — Label Print: pick a box-number range (e.g. 2–5) and generate every box's
# exterior label in one PDF (BoxLabelsPdf, labels_per_box pages per box). Reached from the Menu
# (F3), so it keeps the Menu nav tab active. This controller only renders the range
# form; submitting it POSTs a run to LabelPrintRunsController, which generates the
# PDF in a background job with a live progress bar (#303). Reading/printing labels
# requires Move membership (the authorized box scope); nothing here mutates.
class LabelPrintsController < MoveScopedController
  include LabelPrintForm

  before_action { Current.nav_section = :menu }
  before_action :authorize_read!

  #: () -> untyped
  def show
    render label_print_form
  end

  private

  #: () -> untyped
  def authorize_read!
    authorize! @move, to: :show?, with: MovePolicy
  end
end
