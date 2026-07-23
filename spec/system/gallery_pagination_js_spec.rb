# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for the Gallery's keyset "Load more" (#718). The rack_test
# request spec asserts the cursor walk and the turbo_stream payload; this one
# drives a real browser to prove the in-place append — clicking Load more grows
# the grid without a navigation (scroll survives), the pager retires on the
# last page, and the lightbox discovers the appended tiles (its Stimulus
# targets are queried live at open time, the property the whole design leans
# on).
#
# Like the other JS specs, a real browser runs in a separate server thread, so
# the in-thread `stub_current_tenant` mock can't apply — provision a real
# Apartment tenant resolved from a real subdomain host and sign in via the
# test-login route.
RSpec.describe "Gallery pagination (JS)", :js do
  let(:slug) { "jspager" }
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
    Organizations::Create.new.call(name: "JS Pager Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  def seed_three_photos
    Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      box = create(:box, move: m, number: "1")
      create(:media, move: m, box:, captured_at: 3.days.ago)
      create(:media, move: m, box:, captured_at: 2.days.ago)
      create(:media, move: m, box:, captured_at: 1.day.ago)
      m
    end
  end

  it "appends the next page in place and the lightbox picks the new tiles up" do
    stub_const("GalleriesController::PAGE", 2)
    move = seed_three_photos
    login_as(user: user)
    visit move_gallery_path(move)

    expect(page).to have_css("button[data-lightbox-target='tile']", count: 2)
    expect(page).to have_button(I18n.t("galleries.index.pager.load_more"))

    click_button I18n.t("galleries.index.pager.load_more")

    # The third photo streams into the existing grid — no navigation — and the
    # exhausted pager retires.
    expect(page).to have_css("button[data-lightbox-target='tile']", count: 3)
    expect(page).to have_no_button(I18n.t("galleries.index.pager.load_more"))

    # The appended (last, oldest) tile is live lightbox material.
    expect(page).to have_no_css(".pswp")
    all("button[data-lightbox-target='tile']").last.click
    expect(page).to have_css(".pswp--open")
  end
end
