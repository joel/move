# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::Button do
  it "renders a button element by default" do
    html = described_class.new(label: "Save").call
    expect(html).to include("<button")
    expect(html).to include("Save")
    expect(html).to include("rounded-full")
  end

  it "renders an anchor when given an href" do
    html = described_class.new(label: "Home", href: "/").call
    expect(html).to include('<a href="/"')
  end

  it "renders a disabled button even when an href is present" do
    html = described_class.new(label: "Nope", href: "/", disabled: true).call
    expect(html).to include("<button")
    expect(html).to include("disabled")
  end

  it "applies the sage primary treatment" do
    expect(described_class.new(label: "X").call).to include("bg-accent-sage")
  end

  it "supports a full-width modifier" do
    expect(described_class.new(label: "X", full_width: true).call).to include("w-full")
  end

  it "renders a leading icon" do
    html = described_class.new(label: "Add", icon: Components::Icons::Plus).call
    expect(html).to include("<svg")
  end
end
