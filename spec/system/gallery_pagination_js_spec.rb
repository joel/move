# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for the Gallery's infinite scroll (#718, #720). The
# rack_test request spec asserts the cursor walk and the turbo_stream payload;
# this one drives a real browser to prove the auto-load loop — with the pager
# in reach of the observer the next page streams in with NO click, pages chain
# until the pager retires, and the lightbox discovers the appended tiles (its
# Stimulus targets are queried live at open time, the property the whole
# design leans on). The no-JS fallback (the Load more button + a full-page GET
# at the cursor) stays covered by the request spec — a browser click test
# would race the observer's own submit.
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

  it "auto-loads the next page with no click and the lightbox picks the new tiles up" do
    stub_const("GalleriesController::PAGE", 2)
    move = seed_three_photos
    login_as(user: user)
    visit move_gallery_path(move)

    # Two pages of a short grid: the pager mounts within the observer's reach,
    # so the third photo streams into the existing grid with no interaction —
    # the cascade drains to exhaustion and the pager retires.
    expect(page).to have_css("button[data-lightbox-target='tile']", count: 3)
    expect(page).to have_no_button(I18n.t("galleries.index.pager.load_more"))

    # The appended (last, oldest) tile is live lightbox material.
    expect(page).to have_no_css(".pswp")
    all("button[data-lightbox-target='tile']").last.click
    expect(page).to have_css(".pswp--open")
  end
end
