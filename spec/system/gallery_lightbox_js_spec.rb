# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for the Gallery lightbox. The sibling rack_test request spec
# asserts the grid + dialog render with the right data attributes; this one drives
# a real browser to prove the `lightbox` Stimulus controller is wired up — tapping
# a tile opens the <dialog>, next/prev cycle the photo, and the box link is set.
# Without it, a regression in target wiring or controller loading would make the
# lightbox silently inert.
#
# Like the other JS specs, a real browser runs in a separate server thread, so the
# in-thread `stub_current_tenant` mock can't apply — provision a real Apartment
# tenant resolved from a real subdomain host and sign in via the test-login route.
RSpec.describe "Gallery lightbox (JS)", :js do
  let(:slug) { "jsgallery" }
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
    Organizations::Create.new.call(name: "JS Gallery Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  def seed_two_photos
    Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      create(:media, move: m, box: create(:box, move: m, number: "1"), captured_at: 5.days.ago)
      create(:media, move: m, box: create(:box, move: m, number: "2"), captured_at: 1.hour.ago)
      m
    end
  end

  it "opens the lightbox on tap and sets the box link" do
    move = seed_two_photos
    login_as(user: user)
    visit move_gallery_path(move)

    # No viewer until a tile is tapped; tapping the first (most-recent) tile
    # opens PhotoSwipe (it appends its DOM to <body> on demand).
    expect(page).to have_css("button[data-lightbox-target='tile']", minimum: 2)
    expect(page).to have_no_css(".pswp")
    first("button[data-lightbox-target='tile']").click

    expect(page).to have_css(".pswp--open")
    expect(page).to have_css(".pswp__move-caption", text: /Box 2/i)
    # The caption text is CSS-uppercased, so match the box link by href, not text.
    # Look the box up inside the tenant — the thread has left the schema by now.
    box_two = Apartment::Tenant.switch(slug) { move.boxes.find_by(number: "2") }
    expect(page).to have_css("a.pswp__button--move-view-box[href='#{move_box_path(move, box_two)}']")
  end

  # Drive navigation through PhotoSwipe's own next/prev buttons — a real click is
  # deterministic in headless Chrome, where synthesized key/touch input is not
  # (and swipe/keyboard/zoom are the library's own well-tested engine anyway,
  # live-verified via /product-review). What this asserts is *our* wiring: on a
  # slide change, the custom caption + "view box" chrome follows the new slide.
  it "follows the slide with the caption and box link, and closes" do
    move = seed_two_photos
    login_as(user: user)
    visit move_gallery_path(move)
    first("button[data-lightbox-target='tile']").click
    expect(page).to have_css(".pswp--open")

    box_one = Apartment::Tenant.switch(slug) { move.boxes.find_by(number: "1") }
    click_button(I18n.t("galleries.index.lightbox.next"))
    expect(page).to have_css(".pswp__move-caption", text: /Box 1/i)
    expect(page).to have_css("a.pswp__button--move-view-box[href='#{move_box_path(move, box_one)}']")

    click_button(I18n.t("galleries.index.lightbox.prev"))
    expect(page).to have_css(".pswp__move-caption", text: /Box 2/i)

    # PhotoSwipe's built-in close button carries our closeTitle as its title.
    click_button(I18n.t("galleries.index.lightbox.close"))
    expect(page).to have_no_css(".pswp")
  end
end
