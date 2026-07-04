# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Select (#530).
  class SelectPreview < Lookbook::Preview
    OPTIONS = [%w[Metric metric], %w[Imperial imperial]].freeze

    def default
      render Components::Ui::Select.new(name: "unit", label: "Unit system", options: OPTIONS)
    end

    def with_selected
      render Components::Ui::Select.new(
        name: "unit", label: "Unit system", options: OPTIONS, selected: "imperial"
      )
    end

    # Bare labels — the value defaults to the label when omitted.
    def label_only_options
      render Components::Ui::Select.new(
        name: "room", label: "Room", options: %w[Kitchen Bedroom Garage]
      )
    end

    def with_error
      render Components::Ui::Select.new(
        name: "unit", label: "Unit system", options: OPTIONS, error: "must be chosen"
      )
    end
  end
end
