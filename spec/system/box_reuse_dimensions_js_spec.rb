# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for the "Reuse dimensions" chips (#156). The sibling
# rack_test spec asserts the chips render with the right data attributes; this
# one drives a real browser to prove the Stimulus controller is wired up — a tap
# actually fills the L/W/H inputs (and leaves weight alone). Without this, a
# regression in target wiring or controller loading would make the feature
# silently decorative.
#
# Unlike the stub-based rack_test specs, a real browser runs the request in a
# separate server thread, so `stub_current_tenant` (an in-thread mock) can't
# apply. Instead we provision a real Apartment tenant and resolve it from a real
# subdomain host (`<slug>.lvh.me`, which resolves to 127.0.0.1), then sign in via
# the existing test-login route.
RSpec.describe "Reuse dimensions (JS)", :js do
  let(:slug) { "jschip" }
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
    Organizations::Create.new.call(name: "JS Chip Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  it "fills Length/Width/Height (not weight) and marks the chip pressed on tap" do
    move = Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      create(:box, move: m, number: "1", length_cm: 40, width_cm: 30, height_cm: 25)
      m
    end

    login_as(user: user)
    visit new_move_box_path(move)

    chip = find(".ha-dim-chip", text: "40 × 30 × 25 cm")
    chip.click

    expect(page).to have_field("box[length_cm]", with: "40")
    expect(page).to have_field("box[width_cm]", with: "30")
    expect(page).to have_field("box[height_cm]", with: "25")
    expect(page).to have_field("box[weight_kg]", with: "") # weight is never auto-filled
    expect(chip["aria-pressed"]).to eq("true")
  end
end
