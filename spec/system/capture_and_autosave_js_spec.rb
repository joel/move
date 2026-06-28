# frozen_string_literal: true

require "rails_helper"

# JS-driven coverage for the #162 flows that the rack_test specs can't exercise:
# capture has no shutter button and Item Detail has no Save button — both rely on
# `change->auto-submit#submit` firing in a real browser, Turbo submitting, and
# (for the item) the save-status Turbo Stream rendering. Without this, a Stimulus
# / importmap / Turbo regression would leave users unable to capture or save with
# the rack_test suite still green (Release Bug Scan, #164).
#
# Like the sibling reuse-dimensions JS spec, a real browser runs the request in a
# separate server thread, so we provision a real Apartment tenant resolved from a
# real subdomain host (`<slug>.lvh.me` → 127.0.0.1) and sign in via the test-login
# route. Recognition uses the deterministic Fake provider and `:inline` jobs.
RSpec.describe "Capture & auto-save (JS)", :js do
  let(:slug) { "jscap" }
  let(:user) { create(:user) }
  let(:host) { "#{slug}.lvh.me" }
  let(:image) { Rails.root.join("spec/fixtures/files/sample_image.png") }

  around do |example|
    original_zone = Rails.application.config.x.tenant_zone
    original_app_host = Capybara.app_host
    original_include_port = Capybara.always_include_port

    Rails.application.config.x.tenant_zone = "lvh.me"
    Capybara.app_host = "http://#{host}"
    Capybara.always_include_port = true

    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Organizations::Create.new.call(name: "JS Capture Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  it "auto-submits the captured photo (no shutter) and lands a recognised photo card" do
    move, box = Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      [m, create(:box, move: m, number: "1", status: "packing")]
    end

    login_as(user: user)
    visit move_box_capture_path(move, box)
    expect(page).to have_text(I18n.t("captures.tap_to_capture"))
    expect(page).to have_no_button(I18n.t("captures.shutter", default: "Capture image"))

    # The file input is visually hidden (the whole tile is the label); selecting a
    # file fires `change`, which auto-submits — no button click.
    attach_file("file", image, make_visible: true)

    # Inline recognition (Fake provider) lands a photo-first card: the recognised
    # names show as chips inside ONE card linking to the per-photo detail (D3).
    # Asserting on the rendered card (not a cross-thread DB read) proves the full
    # JS path: file select → auto-submit → recognition.
    #
    # Match with a CSS href-attribute selector, NOT `have_link(text, href:)`:
    # Capybara's link href filter runs `node[:href].match?(regex)` and raises
    # `NoMethodError: undefined method 'match?' for nil` when a candidate <a>
    # momentarily reports a nil href during the Turbo redirect re-render — the
    # CI-only flake (capybara/selector/definition/link.rb:35). `a[href*="…"]` only
    # matches anchors that already carry the href (no nil to crash on), and the
    # text filter retries cleanly on a node swapped mid-navigation.
    # Case-insensitive: the chips are CSS-uppercased (text-label-caps), and the one
    # card carries every recognised name, so match each by regex.
    review_link = %(a[href*="/moves/#{move.id}/boxes/#{box.id}/review/photo"])
    expect(page).to have_css(review_link, text: /Coffee maker/i)
    expect(page).to have_css(review_link, text: /Set of mugs/i)
  end

  it "auto-saves an item edit (no Save button) and shows the Saved badge" do
    move, item = Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      b = create(:box, move: m, number: "1")
      [m, create(:item, :manual, move: m, box: b, name: "Old name")]
    end

    login_as(user: user)
    visit move_item_path(move, item)
    expect(page).to have_field("item[name]", with: "Old name")
    expect(page).to have_no_button(I18n.t("items.show.save"))

    fill_in "item[name]", with: "Vintage Lamp"
    # Blur the field → `change` → Turbo auto-submit → save-status stream.
    find("h2", text: I18n.t("items.show.title")).click

    # The badge label is CSS-uppercased ("SAVED"), so match case-insensitively by id.
    expect(page).to have_css("##{Components::Ui::SaveStatus::ID}", text: /#{I18n.t("items.show.saved")}/i)
    expect(Apartment::Tenant.switch(slug) { item.reload.name }).to eq("Vintage Lamp")
  end
end
