# frozen_string_literal: true

require "rails_helper"

# #619 — the review screen's Retake runs through the in-app viewfinder (the
# camera-capture controller with autostart off), not the native camera app.
# These examples drive the real Stimulus controller against a fake camera:
# `fake_camera_js` is injected over CDP BEFORE any page script runs (the
# controller reads CameraStream.supported at connect, and the lvh.me test host
# is an insecure context with no navigator.mediaDevices at all), and serves a
# canvas captureStream() as the "rear camera". `window.__camera.deny = true`
# makes the next getUserMedia reject like a permission denial.
#
# `:js` specs run in CI only (no chromedriver in the dev container). The
# tenant/host setup and the cross-thread `eventually` read mirror
# review_pending_edits_js_spec.rb.
RSpec.describe "Review retake viewfinder (JS)", :js do
  let(:slug) { "jsretake" }
  let(:user) { create(:user) }
  let(:fake_camera) { {} }
  let!(:seeded) do
    Apartment::Tenant.switch(slug) do
      move = create(:move, created_by: user)
      box = create(:box, move:, number: "1", status: "packing")
      media = create(:media, move:, box:)
      create(:item, move:, box:, source_media: media, name: "Coffee machine", review_state: "pending_review")
      { move:, box:, media:, blob_id: media.image.blob.id }
    end
  end

  def fake_camera_js
    <<~JS
      (() => {
        const camera = window.__camera = { calls: 0, deny: false, streams: [] }
        if (!navigator.mediaDevices) {
          Object.defineProperty(navigator, "mediaDevices", { value: {}, configurable: true })
        }
        // The insecure origin answers the camera permission query "denied",
        // which CameraStream treats as sticky — report a fresh "prompt" so
        // every start() reaches getUserMedia (and the deny flag decides).
        if (navigator.permissions) {
          const query = navigator.permissions.query.bind(navigator.permissions)
          navigator.permissions.query = (descriptor) =>
            descriptor?.name === "camera" ? Promise.resolve({ state: "prompt" }) : query(descriptor)
        }
        navigator.mediaDevices.getUserMedia = async () => {
          camera.calls++
          if (camera.deny) throw new DOMException("Permission denied", "NotAllowedError")
          const canvas = document.createElement("canvas")
          canvas.width = 640
          canvas.height = 480
          const ctx = canvas.getContext("2d")
          const paint = () => { ctx.fillStyle = "#6b8f71"; ctx.fillRect(0, 0, 640, 480) }
          paint()
          setInterval(paint, 100)
          const stream = canvas.captureStream(10)
          camera.streams.push(stream)
          return stream
        }
      })()
    JS
  end

  around do |example|
    original_zone = Rails.application.config.x.tenant_zone
    original_app_host = Capybara.app_host
    original_include_port = Capybara.always_include_port

    Rails.application.config.x.tenant_zone = "lvh.me"
    Capybara.app_host = "http://#{slug}.lvh.me"
    Capybara.always_include_port = true

    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Organizations::Create.new.call(name: "JS Retake Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  # A `before`, not part of `around`: the :js `driven_by` switch to headless
  # Chrome is itself a before hook, so inside `around` the session is still
  # rack_test. The identifier is removed again in `after`, so the fake camera
  # never leaks into another spec on the reused Chrome session.
  before do
    fake_camera[:script] = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: fake_camera_js)
  end

  after do
    next unless fake_camera[:script]

    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: fake_camera[:script]["identifier"])
  end

  def viewfinder = "[data-camera-capture-target='viewfinder']"
  def shutter = "button[data-camera-capture-target='shutter']"
  def take_photo = I18n.t("reviews.photo.retake_camera")
  def camera(expr) = page.evaluate_script("window.__camera.#{expr}")

  # Retry a cross-thread read (see review_pending_edits_js_spec.rb).
  def eventually(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      raise "condition not met within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  def visit_photo
    login_as(user: user)
    visit move_box_review_photo_path(seeded[:move], seeded[:box], seeded[:media])
    expect(page).to have_button(take_photo)
  end

  def open_viewfinder
    click_button take_photo
    expect(page).to have_css(viewfinder, visible: :visible)
    expect(page).to have_css("#{shutter}:not([disabled])")
  end

  it "never starts the camera on its own" do
    visit_photo

    expect(page).to have_css(viewfinder, visible: :hidden)
    expect(page).to have_text(I18n.t("reviews.photo.retake_choose"))
    expect(camera("calls")).to eq(0)
  end

  it "retakes the photo through the viewfinder shutter, with the re-scan kept" do
    visit_photo
    check I18n.t("reviews.photo.retake_rescan")
    open_viewfinder

    find(shutter).click

    expect(page).to have_text(I18n.t("reviews.flash.photo_retaken"))
    eventually do
      Apartment::Tenant.switch(slug) do
        media = seeded[:media].reload
        media.image.blob.id != seeded[:blob_id] &&
          RecognitionRun.exists?(media_id: media.id, rescan: true)
      rescue ActiveRecord::RecordNotFound
        false
      end
    end
  end

  it "releases the camera and folds the viewfinder away on Cancel" do
    visit_photo
    open_viewfinder

    click_button I18n.t("reviews.photo.retake_cancel")

    expect(page).to have_css(viewfinder, visible: :hidden)
    expect(page).to have_button(take_photo)
    expect(camera("streams[0].getVideoTracks()[0].readyState")).to eq("ended")
  end

  it "falls back to the chooser when camera access is denied" do
    visit_photo
    page.execute_script("window.__camera.deny = true")

    click_button take_photo

    expect(page).to have_text(I18n.t("reviews.photo.retake_unavailable"))
    # The denial came from getUserMedia itself, not a pre-denied permission.
    expect(camera("calls")).to eq(1)
    expect(page).to have_css(viewfinder, visible: :hidden)
    expect(page).to have_text(I18n.t("reviews.photo.retake_choose"))
    # The start button stays as the retry affordance.
    expect(page).to have_button(take_photo)
  end
end
