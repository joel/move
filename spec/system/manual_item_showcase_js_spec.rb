# frozen_string_literal: true

require "rails_helper"

# #958 — a manual item add redirects to the box page (a full Turbo visit), where
# the new card renders AFTER every photo card. The request spec proves the card
# carries `data-controller="highlight"`; this drives a real browser to prove the
# controller actually scrolls it into view on a visit, where Turbo's own
# post-render scroll-to-top would otherwise undo the connect-time scroll.
# Tenancy/login setup mirrors box_reuse_dimensions_js_spec.rb.
RSpec.describe "Manual item showcase (JS)", :js do
  let(:slug) { "jsshowcase" }
  let(:user) { create(:user) }
  let(:host) { "#{slug}.lvh.me" }
  let(:in_view_js) do
    <<~JS
      (el => {
        const r = el.getBoundingClientRect()
        return window.scrollY > 0 && r.top >= 0 && r.bottom <= window.innerHeight + 1
      })(arguments[0])
    JS
  end
  let(:card_selector) { "[id^='box_item_'][id$='_card']" }

  around do |example|
    original_zone = Rails.application.config.x.tenant_zone
    original_app_host = Capybara.app_host
    original_include_port = Capybara.always_include_port

    Rails.application.config.x.tenant_zone = "lvh.me"
    Capybara.app_host = "http://#{host}"
    Capybara.always_include_port = true

    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Organizations::Create.new.call(name: "JS Showcase Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  it "scrolls the new item's card into view below the photo cards" do
    add_desk_lamp

    expect(page).to have_link(I18n.t("items.create.view_item"))
    card = find("[data-controller~='highlight']", text: "Desk lamp")
    expect(scrolled_into_view?(card)).to be(true)
  end

  # #968 — the highlight is one-shot. Going Back to the box page restores Turbo's
  # cached snapshot; it must keep the user's restored scroll position and must
  # not flash the card again.
  it "does not replay the highlight or override the scroll on a Back visit" do
    move, box = add_desk_lamp
    card_id = find(card_selector, text: "Desk lamp")[:id]
    expect(page).to have_no_css(".ring-accent-sage", wait: 5) # first flash cleared

    page.execute_script("window.scrollTo(0, 0)")
    sleep 0.5 # let Turbo record the scroll position for restoration
    click_on I18n.t("items.create.view_item")
    expect(page).to have_no_current_path(move_box_path(move, box))

    page.go_back
    expect(page).to have_css("##{card_id}", text: "Desk lamp")
    expect(page).to have_no_css(".ring-accent-sage", wait: 0) # no second flash
    sleep 1 # past the restore scroll and any smooth re-scroll
    expect(page.evaluate_script("window.scrollY")).to eq(0)
  end

  # Signs in, adds "Desk lamp" manually to a box whose photo cards push the new
  # card below the fold, and returns [move, box].
  def add_desk_lamp
    move, box = Apartment::Tenant.switch(slug) do
      m = create(:move, created_by: user)
      b = create(:box, move: m, number: "1")
      create_list(:media, 6, move: m, box: b)
      [m, b]
    end

    login_as(user: user)
    page.current_window.resize_to(1280, 800)
    visit new_move_box_item_path(move, box)
    fill_in "item[name]", with: "Desk lamp"
    click_on I18n.t("items.new.submit")
    [move, box]
  end

  # Polls past the smooth scroll: true once the card sits inside the viewport.
  def scrolled_into_view?(card, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until page.evaluate_script(in_view_js, card)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
    true
  end
end
