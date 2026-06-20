# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Label Print" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    [1, 2, 3].each { |n| create(:box, move:, number: n.to_s, room: create(:room, move:)) }
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "reaches Label Print from the Menu and renders the range form" do
    visit move_menu_path(move)
    expect(page).to have_link(I18n.t("menu.show.label_print"), href: move_label_print_path(move))

    click_on I18n.t("menu.show.label_print")

    expect(page).to have_current_path(move_label_print_path(move), ignore_query: true)
    expect(page).to have_text(I18n.t("label_print.title"))
    expect(page).to have_field(I18n.t("label_print.from"))
    expect(page).to have_field(I18n.t("label_print.to"))
    expect(page).to have_button(I18n.t("label_print.submit"))
  end

  it "submits the form outside Turbo (the PDF response is not HTML)" do
    visit move_label_print_path(move)

    # data-turbo=false → a native submit, so the browser renders/downloads the PDF
    # instead of Turbo silently dropping the non-HTML response.
    expect(page).to have_css('form[data-turbo="false"]')
  end

  it "shows an empty state when the move has no boxes" do
    empty = create(:move, created_by: user, name: "Empty Move")

    visit move_label_print_path(empty)

    expect(page).to have_text(I18n.t("label_print.empty_state"))
    expect(page).to have_no_button(I18n.t("label_print.submit"))
  end
end
