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
  # single page; the Unicode TTF used to overflow one label onto two. On the tiny
  # 62×29mm Brother die-cut (#255) the QR + number + room are bounded shrink-to-fit
  # boxes, so this doubles as the fit guard: an overflow would render 4 pages, not 2.
  it "renders exactly two pages (one label each, no overflow)" do
    room = create(:room, move:, name: "Living Room")
    box = create(:box, move:, room:, number: "9", qr_token: "tok-pages")
    pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-pages").render

    # No pdf-reader dependency: the page-tree /Count is authoritative.
    expect(pdf).to include("/Count 2")
  end

  # #253/#255 — a long, user-controlled room name must not push the label off its
  # one-per-page die-cut. The room name renders shrink-to-fit in its column, so even
  # a very long name keeps each label to one page.
  it "keeps a long room name on a single page (no overflow)" do
    room = create(:room, move:, name: "Upstairs Master Bedroom Walk-in Closet and Storage Nook")
    box = create(:box, move:, room:, number: "9", qr_token: "tok-longroom")
    pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-longroom").render

    expect(pdf).to include("/Count 2")
  end

  # #255 — the page is the 62×29mm Brother QL DK-11209 die-cut, landscape. 62mm ≈
  # 176pt wide, 29mm ≈ 82pt tall (vs the #253 66×80mm ≈ 187×227pt, or A7 209×297pt).
  # Locks the media size: a mismatch is what makes the printer reject the job
  # ("Wrong Roll Type"). The MediaBox carries Prawn's fractional points, so match
  # the leading digits rather than an exact float.
  it "sizes each page to the 62×29mm Brother die-cut label" do
    box = create(:box, move:, room: create(:room, move:), number: "9", qr_token: "tok-size")
    pdf = described_class.new(box:, scan_url: "https://acme.example/scan/tok-size").render

    expect(pdf).to match(%r{/MediaBox \[0 0 175(\.\d+)? 82(\.\d+)?\]})
  end
end
