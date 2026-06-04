# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/style_guide" do
  it "renders the design-system reference in local environments" do
    get "/style_guide"

    expect(response).to be_successful
    expect(response.body).to include("Design system")
  end

  it "renders every recognition state label" do
    get "/style_guide"

    Components::Ui::RecognitionState::STATES.each_key do |state|
      expect(response.body).to include(I18n.t("ui.states.#{state}"))
    end
  end

  it "renders the five navigation destinations" do
    get "/style_guide"

    %w[Boxes Search Scan Summary Menu].each do |label|
      expect(response.body).to include(label)
    end
  end

  it "is hidden (404) outside local environments for anonymous users" do
    allow(Rails.env).to receive(:local?).and_return(false)

    get "/style_guide"

    expect(response).to have_http_status(:not_found)
  end
end
