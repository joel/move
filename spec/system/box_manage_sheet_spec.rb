# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for the B1 "Manage box" bottom sheet (#398) that the
# rack_test specs can't exercise: the ⋮ trigger opens a native <dialog> via
# Stimulus (modal#open), so the secondary actions only become visible — and
# clickable — in a real browser. The lifecycle/delete behaviour itself is covered
# route-level in spec/requests/boxes_spec.rb; here we prove the sheet opens and a
# sheet action (delete, behind a turbo-confirm) reaches the server.
#
# Like the sibling capture JS spec, a real browser runs the request in a separate
# server thread, so we provision a real Apartment tenant resolved from a real
# subdomain host and sign in via the test-login route.
RSpec.describe "Box manage sheet (JS)", :js do
  let(:slug) { "jsmanage" }
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
    Organizations::Create.new.call(name: "JS Manage Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  it "opens the ⋮ sheet, lists the secondary actions, and deletes the box" do
    move, box = Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      [m, create(:box, :with_room, move: m, number: "1", status: "packing")]
    end

    login_as(user: user)
    visit move_box_path(move, box)

    # The secondary actions live inside the closed sheet; opening it via the ⋮
    # trigger (Stimulus modal#open) reveals them.
    find("button[aria-label='#{I18n.t("boxes.manage.trigger")}']").click

    aggregate_failures do
      expect(page).to have_button(I18n.t("boxes.actions.seal"))
      expect(page).to have_link(I18n.t("boxes.actions.print_label"))
      expect(page).to have_button(I18n.t("boxes.actions.delete"))
    end

    accept_confirm { click_button I18n.t("boxes.actions.delete") }

    aggregate_failures do
      expect(page).to have_current_path(move_boxes_path(move))
      expect(page).to have_text(I18n.t("boxes.destroy.deleted", number: "1"))
      expect(Apartment::Tenant.switch(slug) { Box.with_discarded.find(box.id).discarded? }).to be(true)
    end
  end
end
