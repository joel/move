# frozen_string_literal: true

# Shared by LabelPrintsController (renders the form) and LabelPrintRunsController
# (re-renders it on a validation failure): the range-picker view + its SQL-computed
# bounds + box-number param parsing (#303). All bounds come from one SQL row — never
# by loading box rows into Ruby.
module LabelPrintForm
  extend ActiveSupport::Concern

  private

  def label_print_form(error: nil, confirm: nil)
    Views::LabelPrints::Show.new(
      move: @move, error: error, confirm: confirm,
      from: params[:from], to: params[:to], **range_bounds
    )
  end

  # Min/max box number + count, to pre-fill and hint the form. Computed in SQL (one
  # row), not by loading every number into Ruby. `number` is a string column and
  # Arel.sql aggregates come back untyped (as strings), so the numeric MIN/MAX are
  # correct (SQL compared them) but MUST be coerced — &.to_i (the #283 lexical bug).
  def range_bounds
    min, max, count = authorized_scope(@move.boxes)
                      .pick(Arel.sql("MIN(number::bigint), MAX(number::bigint), COUNT(*)"))
    { min_number: min&.to_i, max_number: max&.to_i, box_count: count.to_i }
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
end
