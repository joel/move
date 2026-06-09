# frozen_string_literal: true

# Formats a Move's aggregated volume/weight totals (Moves::VolumeSummary results)
# for display in the Move's unit system. Canonical storage is metric; this
# converts for display only (Technical Foundation §6.2). It returns the numeric
# value and its unit *separately* (Quantity) so the F2 view can size them
# independently — the design shows a large "42.5" next to a small "m³".
class MoveMeasurements
  include UnitConversions

  Quantity = Data.define(:value, :unit)

  def initialize(unit_system: "metric")
    @imperial = unit_system.to_s == "imperial"
  end

  # cm³ → Quantity("42.5", "m³"/"ft³"); nil when no volume is available.
  def volume(cm3)
    return nil if cm3.nil?

    if @imperial
      Quantity.new(value: format_decimal(cm3 / CM3_PER_FT3), unit: "ft³")
    else
      Quantity.new(value: format_decimal(cm3 / CM3_PER_M3), unit: "m³")
    end
  end

  # kilograms → Quantity("1,240", "kg"/"lb"); nil when no weight was recorded.
  def weight(kilograms)
    return nil if kilograms.nil?

    if @imperial
      Quantity.new(value: format_weight(kilograms * LB_PER_KG), unit: "lb")
    else
      Quantity.new(value: format_weight(kilograms), unit: "kg")
    end
  end

  # Finest volume resolution we render (matches BoxMeasurements' 3-decimal m³).
  MIN_VOLUME_LABEL = "<0.001"
  # Finest weight resolution (the box form accepts 0.01-step weights).
  MIN_WEIGHT_LABEL = "<0.01"

  private

  # Trailing-zeros-stripped decimal that never reports a measured nonzero volume
  # as "0": tries 2 decimals (clean for normal totals — 42.50→"42.5", 0.21→
  # "0.21"), escalates to 3 for sub-0.01 values (1,000 cm³ = 0.001 m³→"0.001"),
  # and falls back to a "<0.001" threshold for anything finer.
  def format_decimal(value)
    return "0" if value.zero?

    escalating_decimal(value, precisions: 2..3, threshold: MIN_VOLUME_LABEL)
  end

  # Whole-number weight with a thousands separator for normal totals (design:
  # "1,240 kg"), but a small recorded weight (e.g. 0.4 kg) keeps a decimal rather
  # than rounding to a false "0 kg" — with a "<0.01" threshold for finer values.
  def format_weight(value)
    return "0" if value.zero?

    rounded = value.round
    return ActiveSupport::NumberHelper.number_to_delimited(rounded) if rounded.positive?

    escalating_decimal(value, precisions: 1..2, threshold: MIN_WEIGHT_LABEL)
  end

  # First precision (low→high) whose fixed-point render is nonzero, else the
  # threshold label — so a positive value never collapses to "0".
  def escalating_decimal(value, precisions:, threshold:)
    precisions.each do |precision|
      formatted = format("%.#{precision}f", value).sub(/\.?0+$/, "")
      return formatted unless formatted == "0"
    end
    threshold
  end
end
