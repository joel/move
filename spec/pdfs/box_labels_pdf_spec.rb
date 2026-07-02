# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoxLabelsPdf do
  include PdfHelpers

  let(:move) { create(:move) }

  def entry(box)
    { box: box, scan_url: "https://acme.example/scan/#{box.qr_token}" }
  end

  it "renders 2 pages per box (lid + side) for the whole range" do
    boxes = [2, 3, 4, 5].map do |n|
      create(:box, move:, number: n.to_s, qr_token: "tok-#{n}", room: create(:room, move:))
    end

    pdf = described_class.new(entries: boxes.map { |b| entry(b) }).render

    expect(pdf[0, 4]).to eq("%PDF")
    expect(pdf).to include("/Count 8") # 4 boxes × 2 pages
  end

  it "is single-box parity with BoxLabelPdf (one entry → 2 pages)" do
    box = create(:box, move:, number: "9", qr_token: "tok-one", room: create(:room, move:))
    pdf = described_class.new(entries: [entry(box)]).render

    expect(pdf).to include("/Count 2")
  end

  it "emits `copies` pages per box (Phase 45 labels_per_box)" do
    boxes = [1, 2, 3, 4].map do |n|
      create(:box, move:, number: n.to_s, qr_token: "tok-c#{n}", room: create(:room, move:))
    end

    pdf = described_class.new(entries: boxes.map { |b| entry(b) }, copies: 3).render

    expect(pdf).to include("/Count 12") # 4 boxes × 3 copies
  end

  it "renders a single copy when copies: 1" do
    box = create(:box, move:, number: "7", qr_token: "tok-one1", room: create(:room, move:))
    pdf = described_class.new(entries: [entry(box)], copies: 1).render

    expect(pdf).to include("/Count 1")
  end

  it "yields (done, total) once per box for progress reporting (#303)" do
    boxes = [1, 2, 3].map { |n| create(:box, move:, number: n.to_s, qr_token: "t#{n}", room: create(:room, move:)) }
    progress = []

    described_class.new(entries: boxes.map { |b| entry(b) }).render { |done, total| progress << [done, total] }

    expect(progress).to eq([[1, 3], [2, 3], [3, 3]])
  end

  it "sizes each page to the 62×90mm continuous-tape label" do
    box = create(:box, move:, number: "9", qr_token: "tok-size", room: create(:room, move:))
    pdf = described_class.new(entries: [entry(box)]).render

    expect(pdf).to match(%r{/MediaBox \[0 0 175(\.\d+)? 255(\.\d+)?\]})
  end

  it "renders non-Latin / emoji / smart-punctuation room names without raising" do
    room = create(:room, move:, name: "Café 📦 – 孩子")
    box = create(:box, move:, room:, number: "9", qr_token: "tok-unicode")

    expect { described_class.new(entries: [entry(box)]).render }.not_to raise_error
  end

  it "renders the FRAGILE band for a fragile box without raising (Phase A)" do
    room = create(:room, move:)
    box = create(:box, move:, room:, number: "9", qr_token: "tok-frag", fragile: true)

    expect { described_class.new(entries: [entry(box)]).render }.not_to raise_error
  end

  it "prints the number, room and token on a plain label" do
    room = create(:room, move:, name: "Living Room")
    box = create(:box, move:, room:, number: "7", qr_token: "tok-print")

    text = page_text(described_class.new(entries: [entry(box)], copies: 1).render)

    expect(text).to include("#007").and include("Living Room").and include("tok-print")
  end

  it "prints the box number and the FRAGILE band text on a fragile label (#508)" do
    room = create(:room, move:, name: "Living Room")
    box = create(:box, move:, room:, number: "7", qr_token: "tok-frag-print", fragile: true)

    text = page_text(described_class.new(entries: [entry(box)], copies: 1).render)

    expect(text).to include("#007").and include("FRAGILE")
    expect(text).to include("Living Room").and include("tok-frag-print")
  end

  it "draws the FRAGILE text in white, not the band's own terracotta (#508)" do
    box = create(:box, move:, room: create(:room, move:), number: "7", qr_token: "tok-frag-white", fragile: true)

    pdf = described_class.new(entries: [entry(box)], copies: 1).render

    expect(fill_color_at(pdf, "FRAGILE")).to eq([1.0, 1.0, 1.0])
  end

  it "draws the token near-black — colored via the fragment, print-safe on thermal (#508)" do
    box = create(:box, move:, room: create(:room, move:), number: "7", qr_token: "tok-ink")

    pdf = described_class.new(entries: [entry(box)], copies: 1).render

    # 1A1A1A → 26/255 ≈ 0.102 per channel. Guards both regressions at once: a dead
    # color option rendered ambient black (0.0), and mid-gray would dither on tape.
    expect(fill_color_at(pdf, "tok-ink")).to all(be_within(0.001).of(26.0 / 255))
  end

  # The fragile layout is tuned (details' 0.46 slice) so no text run drops below
  # its designed legibility floor even with the band eating the region — the number
  # clears its floor by only ~0.14pt. fit_text lowers a floor rather than vanish
  # text (#508), so without these pins a nudge to GAP/MARGIN/fractions/font would
  # silently ship smaller print; with them it fails here instead.
  it "keeps every text run at its designed floor or above on a fragile label" do
    box = create(:box, move:, room: create(:room, move:), number: "7", qr_token: "tok-floor", fragile: true)

    pdf = described_class.new(entries: [entry(box)], copies: 1).render

    expect(font_size_at(pdf, "#007")).to be >= BoxLabelsPdf::NUMBER_MIN_SIZE
    expect(font_size_at(pdf, "FRAGILE")).to be >= BoxLabelsPdf::FRAGILE_MIN_SIZE
    expect(font_size_at(pdf, "tok-floor")).to be >= BoxLabelsPdf::TOKEN_MIN_SIZE
  end

  # Long room names wrap to two lines at ROOM_MIN_SIZE on a plain label; the room
  # slice (0.34) clears that by ~0.13pt. Pin the tail so a retune that starts
  # silently truncating the second line fails here (#508's silent-loss class).
  it "prints both lines of a long room name on a plain label" do
    room = create(:room, move:, name: "Upstairs Master Bedroom Walk-in Closet and Storage Nook")
    box = create(:box, move:, room:, number: "7", qr_token: "tok-tail")

    text = page_text(described_class.new(entries: [entry(box)], copies: 1).render)

    # The tail word alone: asserting the "Storage Nook" pair would false-fail if a
    # legitimate retune merely moves the wrap point between the two words.
    expect(text).to include("Nook")
  end

  it "adds label content for a fragile box that a non-fragile box doesn't carry" do
    box = create(:box, move:, room: create(:room, move:), number: "9", qr_token: "tok-frag2", fragile: false)
    plain_pdf = described_class.new(entries: [entry(box)]).render

    box.update!(fragile: true)
    fragile_pdf = described_class.new(entries: [entry(box)]).render

    # The FRAGILE band draws an extra filled rectangle + text run, so the fragile
    # label's content stream is strictly larger than the otherwise-identical plain one.
    expect(fragile_pdf.bytesize).to be > plain_pdf.bytesize
  end
end
