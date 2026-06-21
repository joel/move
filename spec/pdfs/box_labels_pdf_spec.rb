# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoxLabelsPdf do
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
end
