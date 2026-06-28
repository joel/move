# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vocabulary management" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin, name: "Seattle Relocation") }

  before do
    # The creator is the Move's admin (wired by the :move factory).
    # The subdomain elevator sets the tenant on a real request; resolve against
    # the public template here and stub the controller's tenant check.
    stub_current_tenant("acme")
  end

  context "when signed in as an admin" do
    before { login_as(user: admin) }

    it "adds a room end to end" do
      visit move_vocabularies_path(move, "rooms")

      expect(page).to have_text("Manage Rooms")
      fill_in "vocabulary[name]", with: "Mudroom"
      click_button I18n.t("vocabularies.form.add_submit"), exact: true

      expect(page).to have_current_path(move_vocabularies_path(move, "rooms"), ignore_query: true)
      expect(page).to have_text("Mudroom")
      expect(move.rooms.reload.pluck(:name)).to include("Mudroom")
    end

    it "renames a room and the rename propagates" do
      room = create(:room, move:, name: "Kitchn")

      visit move_vocabularies_path(move, "rooms", edit: room.id)
      within "#vocab-#{room.id}" do
        fill_in "vocabulary[name]", with: "Kitchen"
        click_button I18n.t("vocabularies.form.save"), exact: true
      end

      expect(room.reload.name).to eq("Kitchen")
      expect(page).to have_text("Kitchen")
    end

    it "removes an in-use room and detaches its boxes" do
      room = create(:room, move:, name: "Kitchen")
      box = create(:box, move:, room:)

      visit move_vocabularies_path(move, "rooms")
      find("button[aria-label='#{I18n.t("vocabularies.actions.remove", name: "Kitchen")}']").click

      expect(move.rooms.reload.where(name: "Kitchen")).to be_empty
      expect(box.reload.room_id).to be_nil
    end
  end

  context "when signed in as a non-admin member" do
    let(:member) { create(:user) }

    before do
      create(:move_membership, move:, user: member, role: "contributor")
      login_as(user: member)
    end

    it "views the list read-only with no add affordance" do
      create(:room, move:, name: "Kitchen")

      visit move_vocabularies_path(move, "rooms")

      expect(page).to have_text("Kitchen")
      expect(page).to have_no_text(I18n.t("vocabularies.rooms.add"))
      expect(page).to have_no_button(I18n.t("vocabularies.form.add_submit"))
    end
  end
end
