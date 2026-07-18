# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for #690: pending review-page input must survive the advance
# controls. Two loss modes the rack_test suite cannot see:
#
# 1. A dirty inline-rename edit whose blur never fires (iOS Safari doesn't blur a
#    focused input on button taps). Reproduced by driving the mark form with
#    requestSubmit() while focus stays in the field — click_button would fire the
#    blur in desktop Chrome and assert nothing. The fix flushes on
#    turbo:submit-start, so the keepalive PATCH still lands.
# 2. Typed-but-unsubmitted "add a missed item" text, which the advance controls
#    used to discard. The pending-add controller now auto-adds, then advances.
#
# Like the sibling JS specs, the real browser hits the app in a separate server
# thread, so we provision a real Apartment tenant on a real subdomain host
# (`<slug>.lvh.me` → 127.0.0.1). Assertions go through the UI wherever possible:
# transactional fixtures share ONE connection between this thread and the
# server, and Apartment switches search_path on it — a spec-thread
# Tenant.switch read racing a live server request can land in the wrong schema.
# DB reads therefore happen only once the UI proves the flow settled, and retry
# on transient misses (see `eventually`).
RSpec.describe "Review pending edits (JS)", :js do
  let(:slug) { "jsreview" }
  let(:user) { create(:user) }
  let(:host) { "#{slug}.lvh.me" }

  around do |example|
    original_zone = Rails.application.config.x.tenant_zone
    original_app_host = Capybara.app_host
    original_include_port = Capybara.always_include_port

    Rails.application.config.x.tenant_zone = "lvh.me"
    Capybara.app_host = "http://#{host}"
    Capybara.always_include_port = true

    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Organizations::Create.new.call(name: "JS Review Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  # One photo with one pending detection: every advance lands on the box page,
  # so have_current_path doubles as the "walk advanced" assertion.
  def seed_review_photo
    Apartment::Tenant.switch(slug) do
      move = create(:move, created_by: user)
      box = create(:box, move:, number: "1", status: "packing")
      media = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: media, name: "Coffee machine",
                           review_state: "pending_review")
      [move, box, media, item]
    end
  end

  # Retry a cross-thread read: the shared-connection search_path race above can
  # make a single read miss (wrong schema) even after the row committed.
  def eventually(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      met = begin
        yield
      rescue ActiveRecord::RecordNotFound
        false
      end
      return true if met
      raise "condition not met within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  # Holds the mark POST at the fetch layer (Turbo routes its submission through
  # window.fetch, so a never-resolving promise keeps it off the wire entirely —
  # turbo:submit-start, and with it the controller's flush, has already fired
  # by then) and records when the rename PATCH settles. Under transactional
  # fixtures every server thread shares ONE connection and concurrent requests
  # race its Apartment search_path, 404ing either request — a test-env-only
  # artifact (production checks out a connection per request). Holding the POST
  # keeps the keepalive PATCH as the only request in flight, making the
  # example deterministic.
  def hold_mark_submission_and_track_fetch
    page.execute_script(<<~JS)
      window.__renameSettled = false;
      const of_ = window.fetch;
      window.fetch = (...args) => {
        const url = String(args[0] instanceof Request ? args[0].url : args[0]);
        if (url.includes("mark_reviewed")) return new Promise(() => {});
        const p = of_(...args);
        if (url.includes("/rename")) {
          p.then(() => { window.__renameSettled = true }, () => { window.__renameSettled = true });
        }
        return p;
      };
    JS
  end

  it "saves a dirty rename when the mark form submits without a blur" do
    move, box, media, item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)
    find_field(with: "Coffee machine").set("Espresso machine")

    # No blur, no click: submit the mark form directly while focus stays in the
    # field — the exact interleaving that silently lost the edit before #690.
    # The flush must fire on turbo:submit-start, BEFORE the mark POST leaves;
    # the submission itself is held (see the helper), so the advance is
    # asserted by the sequential examples below, and what THIS example guards
    # is the dirty rename surviving the submit.
    hold_mark_submission_and_track_fetch
    page.execute_script(%(document.querySelector('form[action*="mark_reviewed"]').requestSubmit()))

    eventually { page.evaluate_script("window.__renameSettled === true") }
    eventually(timeout: 10) do
      visit move_box_review_photo_path(move, box, media)
      page.has_field?(with: "Espresso machine", wait: 1)
    end
    # The rename itself vouches for the item (Items::Rename sets confirmed), so
    # nothing is pending any more: the explicit-confirm pair is gone and the
    # honest navigation label is back — regardless of how the raced mark fared.
    expect(page).to have_no_button(I18n.t("reviews.photo.mark_reviewed"))
    eventually { Apartment::Tenant.switch(slug) { item.reload.review_state == "confirmed" } }
  end

  it "auto-adds typed add-item text, then marks and advances" do
    move, box, media, item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"

    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first

    # The add is sequenced BEFORE the advance, so landing on the box page proves
    # the add completed; the box page lists the new item.
    expect(page).to have_current_path(move_box_path(move, box), wait: 15)
    expect(page).to have_text(/Cutting board/i)
    eventually do
      Apartment::Tenant.switch(slug) do
        box.items.find_by(name: "Cutting board")&.attributes&.values_at(
          "created_via", "source_media_id", "review_state"
        ) == ["manual", media.id, "confirmed"]
      end
    end
    eventually { Apartment::Tenant.switch(slug) { item.reload.review_state == "confirmed" } }
  end

  it "auto-adds typed add-item text on Ignore without confirming the detection" do
    move, box, media, item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"

    click_link I18n.t("reviews.photo.ignore"), match: :first

    expect(page).to have_current_path(move_box_path(move, box), wait: 15)
    expect(page).to have_text(/Cutting board/i)
    # Ignore left the detection unconfirmed: revisiting the photo still offers
    # the explicit-confirm pair.
    visit move_box_review_photo_path(move, box, media)
    expect(page).to have_button(I18n.t("reviews.photo.mark_reviewed"), match: :first)
    eventually do
      Apartment::Tenant.switch(slug) do
        box.items.find_by(name: "Cutting board")&.created_via == "manual" &&
          item.reload.review_state == "pending_review"
      end
    end
  end

  it "does not resubmit an add the user already submitted before clicking Mark" do
    move, box, _, item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"

    # Manual ✓ then Mark straight after: whether the add is still in flight
    # (guard queues the advance behind it) or already settled (input reset →
    # plain passthrough), the outcome must be ONE item and an advance — never
    # a duplicate from the guard resubmitting the already-submitting form.
    click_button I18n.t("reviews.photo.add")
    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first

    expect(page).to have_current_path(move_box_path(move, box), wait: 15)
    eventually do
      Apartment::Tenant.switch(slug) { box.items.where(name: "Cutting board").one? }
    end
    eventually { Apartment::Tenant.switch(slug) { item.reload.review_state == "confirmed" } }
  end

  # Holds the FIRST add POST on the wire for 800ms so a second value can be
  # typed while that add is genuinely in flight. Requests stay strictly serial
  # (the held add, then the converge add, then the mark POST), so the
  # shared-connection race above never enters the picture.
  def hold_first_add_post
    page.execute_script(<<~JS)
      const of_ = window.fetch;
      window.fetch = (...args) => {
        const url = String(args[0] instanceof Request ? args[0].url : args[0]);
        const method = ((args[0] instanceof Request ? args[0].method : args[1]?.method) || "GET").toLowerCase();
        if (url.includes("/items") && method === "post" && !window.__heldOnce) {
          window.__heldOnce = true;
          return new Promise((resolve) => setTimeout(() => resolve(of_(...args)), 800));
        }
        return of_(...args);
      };
    JS
  end

  it "also submits text typed while an earlier add was still in flight" do
    move, box, _media, item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)
    hold_first_add_post

    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"
    click_button I18n.t("reviews.photo.add")
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Bread knife"
    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first

    expect(page).to have_current_path(move_box_path(move, box), wait: 15)
    eventually do
      Apartment::Tenant.switch(slug) do
        box.items.where(name: "Cutting board").one? && box.items.where(name: "Bread knife").one?
      end
    end
    eventually { Apartment::Tenant.switch(slug) { item.reload.review_state == "confirmed" } }
  end

  it "keeps a deliberately re-typed duplicate name typed during an in-flight add" do
    move, box, _media, _item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)
    hold_first_add_post

    # Duplicate names are valid (two identical candles): re-typing the SAME
    # name during the first add's flight is a second intended item, which a
    # value comparison would drop — the edit-revision flag must not.
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"
    click_button I18n.t("reviews.photo.add")
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"
    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first

    expect(page).to have_current_path(move_box_path(move, box), wait: 15)
    eventually do
      Apartment::Tenant.switch(slug) { box.items.where(name: "Cutting board").count == 2 }
    end
  end

  it "advances normally when nothing is pending (guard passthrough)" do
    move, box, media, item = seed_review_photo

    login_as(user: user)
    visit move_box_review_path(move, box)

    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first

    expect(page).to have_current_path(move_box_path(move, box), wait: 15)
    visit move_box_review_photo_path(move, box, media)
    expect(page).to have_field(with: "Coffee machine")
    expect(page).to have_no_button(I18n.t("reviews.photo.mark_reviewed"))
    eventually { Apartment::Tenant.switch(slug) { item.reload.review_state == "confirmed" } }
  end
end
