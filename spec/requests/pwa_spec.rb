# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PWA" do
  describe "GET /manifest" do
    it "serves a valid, installable web app manifest without authentication" do
      get pwa_manifest_path(format: :json)

      expect(response).to have_http_status(:success)
      manifest = response.parsed_body
      icons = manifest.fetch("icons")
      sizes = icons.map { |i| i["sizes"].to_i }
      aggregate_failures do
        expect(manifest["name"]).to eq(Rails.application.config.x.brand_name)
        expect(manifest["display"]).to eq("standalone")
        expect(manifest["start_url"]).to eq("/")
        expect(manifest["orientation"]).to eq("portrait")
        expect(manifest["theme_color"]).to be_present
        # At least one PNG icon >= 192px (Chrome's installability requirement),
        # an explicit 192 entry for smaller displays, and a maskable variant.
        expect(sizes.max).to be >= 192
        expect(sizes).to include(192)
        expect(icons.any? { |i| i["purpose"] == "maskable" }).to be(true)
      end
    end
  end

  describe "GET /service-worker" do
    it "serves a service worker with a fetch handler without authentication" do
      get pwa_service_worker_path(format: :js)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to include("javascript")
      expect(response.body).to include('addEventListener("fetch"')
    end

    it "implements network-first navigations, cache-first assets, and an offline fallback" do
      get pwa_service_worker_path(format: :js)

      expect(response.body)
        .to include("networkFirstWithOfflineFallback")
        .and include("cacheFirst")
        .and include('request.mode === "navigate"')
        .and include("/offline.html")
      # Versioned by the asset pipeline so a deploy busts the caches.
      expect(response.body).to include("CACHE_VERSION")
      expect(response.body).to include(Rails.application.config.assets.version.to_s)
    end

    it "never caches authenticated navigations, Turbo Streams, or the auth endpoints" do
      get pwa_service_worker_path(format: :js)

      # Auth endpoints + Turbo Stream responses are network-only (the auth layer
      # is fragile — a cached shell would serve stale auth/tenant state).
      expect(response.body)
        .to include("isNetworkOnly")
        .and include("text/vnd.turbo-stream.html")
        .and include('path.startsWith("/auth/")')
    end
  end

  describe "GET /offline.html" do
    it "serves a self-contained offline fallback page without authentication" do
      get "/offline.html"

      expect(response).to have_http_status(:success)
      expect(response.media_type).to include("text/html")
      expect(response.body).to include("offline")
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
