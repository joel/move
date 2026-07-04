# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Card (#530).
  class CardPreview < Lookbook::Preview
    def default
      render Components::Ui::Card.new do |c|
        c.h3(class: "text-headline-md text-text-warm") { "Box 12 — Kitchen" }
        c.p(class: "text-body-md text-on-surface-variant") do
          "Plates, glasses and the good cutlery."
        end
      end
    end

    # Lifts on hover — used for the box grid tiles.
    def interactive
      render Components::Ui::Card.new(interactive: true) do |c|
        c.h3(class: "text-headline-md text-text-warm") { "Box 3 — Living room" }
        c.p(class: "text-body-md text-on-surface-variant") { "Tap to open." }
      end
    end

    # Bottom summary strip (Boxes Home).
    def with_micro_bar
      render Components::Ui::Card.new(micro_bar: ->(c) { c.plain "12/12 packed" }) do |c|
        c.h3(class: "text-headline-md text-text-warm") { "Box 7 — Bedroom" }
      end
    end

    def tight_padding
      render Components::Ui::Card.new(padding: "p-3") do |c|
        c.p(class: "text-body-md text-on-surface-variant") { "Compact card body." }
      end
    end
  end
end
