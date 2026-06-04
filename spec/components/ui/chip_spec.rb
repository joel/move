# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::Chip do
  it "tints rooms with sage" do
    expect(described_class.new(label: "Kitchen", kind: :room).call).to include("text-accent-sage")
  end

  it "tints tags with terracotta" do
    expect(described_class.new(label: "Fragile", kind: :tag).call).to include("text-secondary")
  end

  it "uses a neutral tint for categories" do
    expect(described_class.new(label: "Books", kind: :category).call).to include("text-on-surface-variant")
  end

  it "fills solid sage when selected" do
    html = described_class.new(label: "All", selected: true).call
    expect(html).to include("bg-accent-sage")
    expect(html).to include("text-page")
  end

  it "uses label-caps typography" do
    expect(described_class.new(label: "X").call).to include("text-label-caps")
  end
end
