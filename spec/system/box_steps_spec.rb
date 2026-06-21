# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bulk box steps" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "reaches the page from the Menu and renders a confirm-guarded seal button" do
    create_list(:box, 2, :with_room, move:, status: "packing")

    visit move_menu_path(move)
    click_on I18n.t("menu.show.box_steps")

    expect(page).to have_current_path(move_box_steps_path(move), ignore_query: true)
    expect(page).to have_text(I18n.t("box_steps.show.title"))
    # The confirm guard is present on the button (rack_test submits past it).
    label = I18n.t("box_steps.show.steps.sealed.button", count: 2)
    expect(find_button(label)["data-turbo-confirm"]).to eq(I18n.t("box_steps.show.steps.sealed.confirm"))
  end

  it "seals all packing boxes and refreshes the available steps" do
    create_list(:box, 2, :with_room, move:, status: "packing")

    visit move_box_steps_path(move)
    click_on I18n.t("box_steps.show.steps.sealed.button", count: 2)

    expect(page).to have_text(
      I18n.t("box_steps.create.transitioned", count: 2, status: I18n.t("boxes.status.sealed"))
    )
    expect(move.boxes.where(status: "sealed").count).to eq(2)
    # The seal step no longer appears (no packing boxes left); the next step does.
    expect(page).to have_no_button(I18n.t("box_steps.show.steps.sealed.button", count: 2))
    expect(page).to have_button(I18n.t("box_steps.show.steps.in_transit.button", count: 2))
  end
end
