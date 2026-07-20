# frozen_string_literal: true

require "rails_helper"

# #702 — renderer-level checks for the movers-facing declaration. The end-to-end
# privacy invariant (a real Move's box numbers / room names never reach the PDF)
# lives in spec/requests/insurance_declarations_spec.rb; here we pin the layout
# contract over hand-built sections.
RSpec.describe InsuranceDeclarationPdf do
  include PdfHelpers

  let(:move) { build(:move, name: "Autumn Relocation", planned_on: Date.new(2026, 9, 1)) }

  def render(sections:, total: nil)
    total ||= sections.sum { |s| s[:lines].sum(&:last) }
    described_class.new(move: move, sections: sections, total_items: total).render
  end

  it "renders family headings with aggregated quantities, Miscellaneous last" do
    pdf = render(sections: [
                   { family: "batteries & power", lines: [["AA batteries", 2]] },
                   { family: "kitchenware", lines: [["Mug", 3], ["Plates", 1]] },
                   { family: nil, lines: [["Odd lamp", 1]] } # nil renders as Miscellaneous
                 ])

    text = document_text(pdf)
    aggregate_failures do
      expect(text).to include("Batteries & power").and include("Kitchenware")
      expect(text).to include("Mug").and include("3")
      expect(text.index("Kitchenware")).to be < text.index("Miscellaneous")
      expect(text).to include("7 items in 3 categories")
    end
  end

  it "documents the privacy intent on the artifact itself" do
    pdf = render(sections: [{ family: "kitchenware", lines: [["Mug", 1]] }])

    expect(document_text(pdf)).to include("intentionally contains no box numbers")
  end

  it "wraps long item names in full up to the explicit ellipsis (no silent width clipping)" do
    long = "Hand-carved walnut jewellery cabinet with seven velvet-lined drawers, " \
           "brass butterfly hinges and the little key kept in the blue envelope somewhere safe"
    pdf = render(sections: [{ family: "furniture", lines: [[long, 1]] }])

    text = document_text(pdf).gsub(/\s+/, " ")
    expect(text).to include("brass butterfly hinges") # content beyond one rendered line survives
    expect(text).to include("...") # the Ruby truncation marker prints
  end

  it "renders Unicode item names without crashing (the #85 AFM trap)" do
    pdf = nil
    expect do
      pdf = render(sections: [{ family: "kitchenware", lines: [["Ćevapi šerpa – Große 📦", 1]] }])
    end.not_to raise_error
    expect(pdf[0, 4]).to eq("%PDF")
  end

  it "renders the empty state for a move with no items" do
    pdf = render(sections: [], total: 0)

    expect(document_text(pdf)).to include("No items recorded yet.")
  end
end
