# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::SaveStatus do
  it "renders a hidden placeholder when idle, still carrying the stable id" do
    html = described_class.new.call
    expect(html).to include(%(id="#{described_class::ID}"))
    expect(html).to include("hidden")
  end

  it "shows a sage 'Saved' badge that auto-fades on save" do
    html = described_class.new(state: :saved).call
    expect(html).to include(I18n.t("items.show.saved"))
    expect(html).to include("text-accent-sage")
    expect(html).to include('data-controller="save-status"') # the fade controller
  end

  it "shows a persistent error badge (no fade controller) with the given message" do
    html = described_class.new(state: :error, message: "Name can’t be blank").call
    expect(html).to include("text-error")
    expect(html).to include("Name can")
    expect(html).not_to include('data-controller="save-status"')
  end
end
