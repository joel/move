# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::ProgressBar (#530).
  class ProgressBarPreview < Lookbook::Preview
    def default
      render Components::Ui::ProgressBar.new(value: 7, max: 12)
    end

    def with_label
      render Components::Ui::ProgressBar.new(value: 7, max: 12, label: "Boxes packed")
    end

    def complete
      render Components::Ui::ProgressBar.new(value: 12, max: 12, label: "Boxes packed")
    end

    def empty
      render Components::Ui::ProgressBar.new(value: 0, max: 12, label: "Boxes packed")
    end

    # Terracotta fill — the secondary tone.
    def terracotta
      render Components::Ui::ProgressBar.new(value: 4, max: 12, label: "Fragile boxes", tone: :terracotta)
    end
  end
end
