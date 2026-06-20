# frozen_string_literal: true

# E1 — Label Print: pick a box-number range (e.g. 2–5) and print every box's
# exterior label in one PDF (BoxLabelsPdf, 2 pages per box). Reached from the Menu
# (F3), so it keeps the Menu nav tab active. Reading labels requires Move
# membership (the authorized box scope); nothing here mutates.
class LabelPrintsController < MoveScopedController
  # Guard against an accidental hundreds-of-boxes print job.
  MAX_LABELS = 200

  before_action { Current.nav_section = :menu }
  before_action :authorize_read!

  def show
    render form_view
  end

  def print
    from, to = requested_range
    return reject(:invalid_range) if from.nil? || to.nil? || from > to

    scope = boxes_in_range(from, to)
    count = scope.count
    return reject(:empty) if count.zero?
    return reject(:too_many) if count > MAX_LABELS

    # Load rooms only now that we're committed to rendering (the QR + number + room
    # go on each label); rejecting earlier never touches a room (Bullet).
    entries = scope.includes(:room).map do |box|
      { box: box, scan_url: move_scan_resolve_url(@move, box.qr_token) }
    end
    send_data BoxLabelsPdf.new(entries: entries).render,
              filename: filename(from, to), type: "application/pdf", disposition: "inline"
  end

  private

  def authorize_read!
    authorize! @move, to: :show?, with: MovePolicy
  end

  def reject(reason)
    message = t("label_print.errors.#{reason}", max: MAX_LABELS)
    render form_view(error: message), status: :unprocessable_content
  end

  def form_view(error: nil)
    Views::LabelPrints::Show.new(
      move: @move, error: error, from: params[:from], to: params[:to], **range_bounds
    )
  end

  def requested_range
    [param_int(:from), param_int(:to)]
  end

  # A valid box-number bound from the param, else nil (non-numeric / blank / ≤ 0 /
  # above the bigint range — a bound past Box::MAX_NUMBER would raise
  # ActiveRecord::RangeError on the number::bigint comparison, i.e. a 500).
  def param_int(key)
    value = params[key].to_s.strip
    return nil unless value.match?(/\A\d+\z/)

    number = value.to_i
    return nil unless number.positive? && number <= Box::MAX_NUMBER

    number
  end

  def boxes_in_range(from, to)
    authorized_scope(@move.boxes)
      .where("number::bigint BETWEEN ? AND ?", from, to)
      .ordered
  end

  # Min/max box number + count, to pre-fill and hint the form (default = all boxes).
  # Computed in SQL (one row), not by loading every number into Ruby. number is a
  # string column and Arel.sql aggregates come back untyped (as strings), so the
  # numeric MIN/MAX are correct (SQL compared them) but must be coerced — to_i.
  def range_bounds
    min, max, count = authorized_scope(@move.boxes)
                      .pick(Arel.sql("MIN(number::bigint), MAX(number::bigint), COUNT(*)"))
    { min_number: min&.to_i, max_number: max&.to_i, box_count: count.to_i }
  end

  def filename(from, to)
    "boxes-#{format("%03d", from)}-#{format("%03d", to)}-labels.pdf"
  end
end
