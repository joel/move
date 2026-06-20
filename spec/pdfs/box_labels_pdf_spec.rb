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
