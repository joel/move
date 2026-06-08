# frozen_string_literal: true

require "rails_helper"

# Regression for #85 — see box_label_pdf_spec.rb. A Unicode TTF lets the manifest
# render user-supplied item/category/tag names with non-Latin scripts, emoji, or
# smart punctuation without raising Prawn::Errors::IncompatibleStringEncoding.
RSpec.describe BoxManifestPdf do
  let(:move) { create(:move) }

  it "renders a manifest with Unicode item / category / tag names" do
    box = create(:box, :with_room, move:, number: "9")
    category = create(:category, move:, name: "Électronique")
    tag = create(:tag, move:, name: "Fragile ✨")
    create(:item, :manual, move:, box:, name: "Lámpara – brass 📦", category:, tags: [tag])
    items = box.items.includes(:category, :tags).ordered.to_a

    pdf = nil
    expect { pdf = described_class.new(box:, items:).render }.not_to raise_error
    expect(pdf[0, 4]).to eq("%PDF")
  end
end
