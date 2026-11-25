# frozen_string_literal: true

require "rails_helper"

# #619 — the review screen's Retake runs through the in-app viewfinder (the
# camera-capture controller with autostart off), not the native camera app.
# These examples drive the real Stimulus controller against the fake camera in
# spec/support/fake_camera_helpers.rb (injected over CDP before any page
# script runs; `deny` / `hold` + `release()` steer getUserMedia).
#
# `:js` specs run in CI only (no chromedriver in the dev container). The
# tenant/host setup and the cross-thread `eventually` read mirror
# review_pending_edits_js_spec.rb.
RSpec.describe "Review retake viewfinder (JS)", :js do
  let(:slug) { "jsretake" }
  let(:user) { create(:user) }
  let!(:seeded) do
    Apartment::Tenant.switch(slug) do
      move = create(:move, created_by: user)
      box = create(:box, move:, number: "1", status: "packing")
      media = create(:media, move:, box:)
      create(:item, move:, box:, source_media: media, name: "Coffee machine", review_state: "pending_review")
      { move:, box:, media:, blob_id: media.image.blob.id }
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
    Organizations::Create.new.call(name: "JS Retake Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  # FakeCameraHelpers (spec/support): installed from a `before`, removed in `after`.
  before { install_fake_camera }
  after { remove_fake_camera }

  def viewfinder = "[data-camera-capture-target='viewfinder']"
  def shutter = "button[data-camera-capture-target='shutter']"
  def pending_status = "[data-camera-capture-target='pending']"
  def rescan_box = "input[name='rerun_recognition']"
  def take_photo = I18n.t("reviews.photo.retake_camera")
  def cancel = I18n.t("reviews.photo.retake_cancel")
  def focused_target = page.evaluate_script("document.activeElement?.dataset.cameraCaptureTarget")
  def focused_text = page.evaluate_script("document.activeElement?.textContent").to_s
  def focused_name = page.evaluate_script("document.activeElement?.name")

  def visit_photo
    login_as(user: user)
    visit move_box_review_photo_path(seeded[:move], seeded[:box], seeded[:media])
    expect(page).to have_button(take_photo)
  end

  def open_viewfinder
    click_button take_photo
    expect(page).to have_css(viewfinder, visible: :visible)
    expect(page).to have_css("#{shutter}:not([disabled])")
    # The start button hid under the user's focus; focus follows to the shutter.
    expect(focused_target).to eq("shutter")
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
    # Cancel hid itself; focus returns to the re-revealed start button.
    expect(focused_text).to include(take_photo)
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

  # #991 — once the shutter hands a frame to the upload pipeline, the POST
  # will replace the photo whatever the user does next: Cancel must not
  # pretend otherwise.
  describe "while the retake upload is pending" do
    # Keep the frame in the pre-submit window: capture-upload's requestSubmit
    # is stubbed, so the upload lock stays held until the spec settles it.
    def hold_submission
      page.execute_script(<<~JS)
        const form = document.querySelector("form[data-controller~='capture-upload']")
        window.__submits = 0
        form.requestSubmit = () => { window.__submits++ }
      JS
    end

    # Settle only once the held submit was attempted (the pipeline's downscale
    # is async), as a real turbo:submit-end would.
    def settle_submission
      eventually { page.evaluate_script("window.__submits").positive? }
      page.execute_script(<<~JS)
        const form = document.querySelector("form[data-controller~='capture-upload']")
        form.dispatchEvent(new CustomEvent("turbo:submit-end", { bubbles: true, detail: {} }))
      JS
    end

    def shoot_with_submission_held
      visit_photo
      open_viewfinder
      hold_submission
      expect(page).to have_no_css(pending_status, visible: :visible)
      find(shutter).click
    end

    it "hides Cancel and shows the replacing status once the shutter hands off a frame" do
      shoot_with_submission_held

      expect(page).to have_css("#{pending_status}[role='status']", visible: :visible,
                                                                   text: I18n.t("reviews.photo.retake_pending"))
      expect(page).to have_no_button(cancel)
      expect(page).to have_css("#{shutter}[disabled]")
      # The keyboard user's shutter went inert; focus lands on the status.
      expect(focused_target).to eq("pending")
    end

    it "brings Cancel back when the upload settles" do
      shoot_with_submission_held
      expect(page).to have_css(pending_status, visible: :visible)

      settle_submission

      expect(page).to have_button(cancel)
      expect(page).to have_css(pending_status, visible: :hidden)
      expect(page).to have_css("#{shutter}:not([disabled])")
    end

    # #995 — the status that held focus hides on settle; focus must move on
    # to the next live control, not drop to the body.
    it "moves focus from the status to the re-armed shutter when the upload settles" do
      shoot_with_submission_held
      expect(page).to have_css(pending_status, visible: :visible)
      expect(focused_target).to eq("pending")

      settle_submission

      expect(page).to have_css("#{shutter}:not([disabled])")
      expect(focused_target).to eq("shutter")
    end

    it "moves focus from the status to the start control when the camera died meanwhile" do
      shoot_with_submission_held
      expect(page).to have_css(pending_status, visible: :visible)
      expect(focused_target).to eq("pending")
      # The camera dies mid-upload and its one automatic retry is denied.
      page.execute_script(<<~JS)
        window.__camera.deny = true
        window.__camera.streams[0].getVideoTracks()[0].dispatchEvent(new Event("ended"))
      JS
      expect(page).to have_text(I18n.t("reviews.photo.retake_unavailable"))
      expect(focused_target).to eq("pending")

      settle_submission

      expect(page).to have_css(pending_status, visible: :hidden)
      expect(focused_text).to include(take_photo)
    end
  end

  # #992 — the permission prompt can stay open a while; a late resolve must not
  # pull focus back from wherever the user has moved it since.
  describe "focus when the camera resolves late" do
    def start_by_keyboard_then_move_focus
      visit_photo
      page.execute_script("window.__camera.hold = true")
      find_button(take_photo).send_keys(:enter)
      eventually { camera("held.length") == 1 }
      page.execute_script("document.querySelector(\"#{rescan_box}\").focus()")
      expect(focused_name).to eq("rerun_recognition")
    end

    it "leaves focus alone when access is granted" do
      start_by_keyboard_then_move_focus

      page.execute_script("window.__camera.release()")

      expect(page).to have_css("#{shutter}:not([disabled])", visible: :visible)
      expect(focused_name).to eq("rerun_recognition")
    end

    it "leaves focus alone when access is denied" do
      start_by_keyboard_then_move_focus
      page.execute_script("window.__camera.deny = true")

      page.execute_script("window.__camera.release()")

      expect(page).to have_text(I18n.t("reviews.photo.retake_unavailable"))
      expect(focused_name).to eq("rerun_recognition")
    end

    it "still moves focus to the shutter when the user left it alone" do
      visit_photo
      page.execute_script("window.__camera.hold = true")
      find_button(take_photo).send_keys(:enter)
      eventually { camera("held.length") == 1 }

      page.execute_script("window.__camera.release()")

      expect(page).to have_css("#{shutter}:not([disabled])", visible: :visible)
      expect(focused_target).to eq("shutter")
    end
  end

  # #987 — Turbo can cache the page (turbo:before-cache → teardown) without
  # replacing it; the live camera must come back instead of going dark.
  describe "Turbo caching the page" do
    it "restarts the camera after a history pop Turbo didn't create" do
      visit_photo
      open_viewfinder

      pop_history_outside_turbo

      eventually { camera("calls") == 2 && camera("liveTrack(1)") }
      expect(camera("liveTrack(0)")).to be(false)
      expect(page).to have_css(viewfinder, visible: :visible)
      expect(page).to have_css("#{shutter}:not([disabled])")
    end

    it "restarts the camera when Turbo renders without replacing the page" do
      visit_photo
      open_viewfinder

      cache_then_render_in_place

      eventually { camera("calls") == 2 && camera("liveTrack(1)") }
      expect(camera("liveTrack(0)")).to be(false)
      expect(page).to have_css(viewfinder, visible: :visible)
    end

    it "does not start a camera the user never opened" do
      visit_photo

      cache_then_render_in_place
      pop_history_outside_turbo

      expect(page).to have_css(viewfinder, visible: :hidden)
      expect(camera("calls")).to eq(0)
    end

    it "releases the camera on a normal navigation away" do
      visit_photo
      open_viewfinder

      page.execute_script("window.Turbo.visit('#{move_box_path(seeded[:move], seeded[:box])}')")

      expect(page).to have_current_path(move_box_path(seeded[:move], seeded[:box]))
      eventually { camera("liveTrack(0)") == false }
      expect(camera("calls")).to eq(1)
    end
  end
end
