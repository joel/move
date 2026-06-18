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

  # #162 — print two identical labels per box in one job, and each label fits a
  # single page; the Unicode TTF used to overflow one label onto two. At the 66×80mm
  # roll size (#253) there is ~70pt less vertical room than the old A7 page, so this
  # doubles as the fit regression: an overflowed label would render 4 pages, not 2.
  it "renders exactly two pages (one label each, no overflow)" do
    room = create(:room, move:, name: "Living Room")
    box = create(:box, move:, room:, number: "9", qr_token: "tok-pages")
    pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-pages").render

    # No pdf-reader dependency: the page-tree /Count is authoritative.
    expect(pdf).to include("/Count 2")
  end

  # #253 — a long, user-controlled room name must not wrap onto a second page (the
  # small 66×80mm roll has little slack). The room name renders shrink-to-fit into
  # the remaining space, so even a very long name keeps each label to one page.
  it "keeps a long room name on a single page (no overflow)" do
    room = create(:room, move:, name: "Upstairs Master Bedroom Walk-in Closet and Storage Nook")
    box = create(:box, move:, room:, number: "9", qr_token: "tok-longroom")
    pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-longroom").render

    expect(pdf).to include("/Count 2")
  end

  # #253 — the page is the 66×80mm thermal label, not A7 (74×105mm). 66mm ≈ 187pt
  # wide, 80mm ≈ 227pt tall; A7 would be 209×297pt. Locks the media size against an
  # accidental revert. The MediaBox carries Prawn's fractional points, so match the
  # leading digits rather than an exact float.
  it "sizes each page to the 66×80mm label roll" do
    box = create(:box, move:, room: create(:room, move:), number: "9", qr_token: "tok-size")
    pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-size").render

    expect(pdf).to match(%r{/MediaBox \[0 0 187(\.\d+)? 226(\.\d+)?\]})
  end
end
