# frozen_string_literal: true

require "rails_helper"

# #987 — every in-app camera surface releases its camera on turbo:before-cache
# (the E2 QR scanner since #618; the camera-capture surfaces since #987).
# Turbo can cache the page WITHOUT replacing it (a history entry Turbo didn't
# create, a morphing refresh), so no disconnect/connect follows; the surface
# must then restart the camera instead of leaving a silent black viewfinder,
# while a normal navigation away still releases it.
#
# The fake camera (FakeCameraHelpers) serves a plain sage frame, so jsQR never
# decodes anything and the scanner keeps scanning. `:js` specs run in CI only
# (no chromedriver in the dev container). Tenant/host setup mirrors
# review_retake_viewfinder_js_spec.rb.
RSpec.describe "In-app camera across Turbo caching (JS)", :js do
  let(:slug) { "jsscancache" }
  let(:user) { create(:user) }
  let!(:seeded) do
    Apartment::Tenant.switch(slug) do
      move = create(:move, created_by: user)
      { move:, box: create(:box, move:, number: "1", status: "packing") }
    end
  end

  around do |example|
    original_zone = Rails.application.config.x.tenant_zone
    original_app_host = Capybara.app_host
    original_include_port = Capybara.always_include_port

    Rails.application.config.x.tenant_zone = "lvh.me"
    Capybara.app_host = "http://#{slug}.lvh.me"
    Capybara.always_include_port = true

    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Organizations::Create.new.call(name: "JS Scan Cache Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  before { install_fake_camera }
  after { remove_fake_camera }

  def box_path = move_box_path(seeded[:move], seeded[:box])

  # A real Turbo visit away (same document, so window.__camera survives it).
  def navigate_away
    page.execute_script("window.Turbo.visit('#{box_path}')")
    expect(page).to have_current_path(box_path)
  end

  describe "the E2 QR scanner" do
    def fallback = "[data-qr-scanner-target='fallback']"

    def visit_scanner
      login_as(user: user)
      visit move_scan_path(seeded[:move])
      eventually { camera("calls") == 1 && camera("liveTrack(0)") }
    end

    it "restarts the camera after a history pop Turbo didn't create" do
      visit_scanner

      pop_history_outside_turbo

      eventually { camera("calls") == 2 && camera("liveTrack(1)") }
      expect(camera("liveTrack(0)")).to be(false)
      expect(page).to have_css(fallback, visible: :hidden)
    end

    it "restarts the camera when Turbo renders without replacing the page" do
      visit_scanner

      cache_then_render_in_place

      eventually { camera("calls") == 2 && camera("liveTrack(1)") }
      expect(camera("liveTrack(0)")).to be(false)
    end

    it "reveals the fallback, not a black viewfinder, when the restarted camera is denied" do
      visit_scanner
      page.execute_script("window.__camera.deny = true")

      pop_history_outside_turbo

      expect(page).to have_css(fallback, visible: :visible)
      expect(camera("calls")).to eq(2)
      expect(camera("liveTrack(0)")).to be(false)
    end

    it "releases the camera on a normal navigation away" do
      visit_scanner

      navigate_away

      eventually { camera("liveTrack(0)") == false }
      expect(camera("calls")).to eq(1)
    end
  end

  # Headless Chrome is a fine pointer, so B2 waits for "Use camera".
  describe "the B2 capture viewfinder" do
    def viewfinder = "[data-camera-capture-target='viewfinder']"

    def open_capture_camera
      login_as(user: user)
      visit move_box_capture_path(seeded[:move], seeded[:box])
      click_button I18n.t("captures.viewfinder.use_camera")
      expect(page).to have_css(viewfinder, visible: :visible)
      eventually { camera("liveTrack(0)") }
    end

    it "restarts the camera after a history pop Turbo didn't create" do
      open_capture_camera

      pop_history_outside_turbo

      eventually { camera("calls") == 2 && camera("liveTrack(1)") }
      expect(camera("liveTrack(0)")).to be(false)
      expect(page).to have_css(viewfinder, visible: :visible)
    end

    it "releases the camera on a normal navigation away" do
      open_capture_camera

      navigate_away

      eventually { camera("liveTrack(0)") == false }
      expect(camera("calls")).to eq(1)
    end
  end
end
