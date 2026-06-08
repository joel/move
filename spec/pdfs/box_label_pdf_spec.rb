# frozen_string_literal: true

require "rails_helper"

# Regression for #85: PDFs rendered user text with Prawn's built-in (Windows-1252)
# font and 500'd on non-Latin / emoji / smart-punctuation names. With a Unicode
# TTF embedded, any UTF-8 string renders (unsupported glyphs degrade to blanks)
# without raising Prawn::Errors::IncompatibleStringEncoding.
RSpec.describe BoxLabelPdf do
  let(:move) { create(:move) }

  it "renders a label with non-Latin / emoji / smart-punctuation names" do
    room = create(:room, move:, name: "Café 📦 – 孩子")
    box = create(:box, move:, room:, number: "9", qr_token: "tok-unicode")

    pdf = nil
    expect { pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-unicode").render }
      .not_to raise_error
    expect(pdf[0, 4]).to eq("%PDF")
  end
end
