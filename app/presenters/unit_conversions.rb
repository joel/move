# frozen_string_literal: true

# Single source for the metric↔imperial conversion factors shared by the
# measurement presenters (BoxMeasurements, MoveMeasurements). Canonical storage
# is always metric (cm/kg); these convert for *display only* and changing the
# Move's unit system never reinterprets stored values (Technical Foundation §6.2).
module UnitConversions
  CM_PER_INCH = 2.54
  CM3_PER_M3 = 1_000_000.0
  CM3_PER_FT3 = 28_316.846592
  LB_PER_KG = 2.2046226218
end
