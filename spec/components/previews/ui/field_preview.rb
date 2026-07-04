# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Field (#530).
  class FieldPreview < Lookbook::Preview
    def default
      render Components::Ui::Field.new(name: "name", label: "Box name")
    end

    def with_value
      render Components::Ui::Field.new(name: "name", label: "Box name", value: "Kitchen — plates")
    end

    def with_placeholder
      render Components::Ui::Field.new(
        name: "description", label: "Contents", placeholder: "What's inside?"
      )
    end

    def with_hint
      render Components::Ui::Field.new(
        name: "weight", label: "Weight", type: "number",
        hint: "Rounded to the nearest kilogram."
      )
    end

    # The error replaces the hint and turns the edge terracotta.
    def with_error
      render Components::Ui::Field.new(
        name: "name", label: "Box name", value: "", error: "can't be blank"
      )
    end

    def required
      render Components::Ui::Field.new(name: "email", label: "Email", type: "email", required: true)
    end
  end
end
