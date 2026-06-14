# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PWA" do
  describe "GET /manifest" do
    it "serves a valid, installable web app manifest without authentication" do
      get pwa_manifest_path(format: :json)

      expect(response).to have_http_status(:success)
      manifest = response.parsed_body
      expect(manifest["name"]).to eq(Rails.application.config.x.brand_name)
      expect(manifest["display"]).to eq("standalone")
      expect(manifest["start_url"]).to eq("/")
      # At least one PNG icon >= 192px (Chrome's installability requirement).
      sizes = manifest.fetch("icons").map { |i| i["sizes"].to_i }
      expect(sizes.max).to be >= 192
      expect(manifest["theme_color"]).to be_present
    end
  end

  describe "GET /service-worker" do
    it "serves a service worker with a fetch handler without authentication" do
      get pwa_service_worker_path(format: :js)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to include("javascript")
      expect(response.body).to include('addEventListener("fetch"')
    end
  end

  describe "the app shell head" do
    let(:user) { create(:user) }

    before { stub_current_user(user) }

    it "links the manifest and PWA install metadata" do
      get account_url

      expect(response.body).to include('rel="manifest"')
      expect(response.body).to include('rel="apple-touch-icon"')
      expect(response.body).to include('name="application-name"')
    end
  end
end
