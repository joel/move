# frozen_string_literal: true

# Formats a Box's canonical metric dimensions/volume/weight for display in the
# Move's unit system (Technical Foundation §6.2: canonical storage, display
# conversion; changing the unit system never reinterprets stored values).
# Plain Ruby — no `measured` gem dependency for this small conversion surface.
class BoxMeasurements
  CM_PER_INCH = 2.54
  CM3_PER_FT3 = 28_316.846592
  LB_PER_KG = 2.2046226218

  def initialize(box, unit_system: "metric")
    @box = box
    @imperial = unit_system.to_s == "imperial"
  end

  # e.g. "40 × 30 × 25 cm" / "15.7 × 11.8 × 9.8 in" — nil if any dimension absent.
  def dimensions
    return nil if @box.missing_dimensions?

    values = [@box.length_cm, @box.width_cm, @box.height_cm]
    values = values.map { |cm| cm / CM_PER_INCH } if @imperial
    "#{values.map { |v| format_number(v) }.join(" × ")} #{@imperial ? "in" : "cm"}"
  end

  # e.g. "0.030 m³" / "1.06 ft³" — nil if dimensions incomplete.
  def volume
    cm3 = @box.volume_cm3
    return nil unless cm3

    if @imperial
      "#{format("%.2f", cm3 / CM3_PER_FT3)} ft³"
    else
      "#{format("%.3f", cm3 / 1_000_000.0)} m³"
    end
  end

  # e.g. "8.0 kg" / "17.6 lb" — nil if no weight recorded.
  def weight
    kg = @box.weight_kg
    return nil if kg.blank?

    @imperial ? "#{format("%.1f", kg * LB_PER_KG)} lb" : "#{format("%.1f", kg)} kg"
  end

  private

  # Whole numbers render without a trailing ".0"; fractional to one decimal.
  def format_number(value)
    value == value.to_i ? value.to_i.to_s : format("%.1f", value)
  end
end
