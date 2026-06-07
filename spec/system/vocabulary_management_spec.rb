# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vocabulary management" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin, name: "Seattle Relocation") }

  before do
    create(:move_membership, :admin, move:, user: admin)
    # The subdomain elevator sets the tenant on a real request; resolve against
    # the public template here and stub the controller's tenant check.
    stub_current_tenant("acme")
  end

  context "when signed in as an admin" do
    before { login_as(user: admin) }

    it "adds a category end to end" do
      visit move_vocabularies_path(move, "categories")

      expect(page).to have_text("Manage Categories")
      fill_in "vocabulary[name]", with: "Kitchenware"
      click_button I18n.t("vocabularies.form.add_submit"), exact: true

      expect(page).to have_current_path(move_vocabularies_path(move, "categories"), ignore_query: true)
      expect(page).to have_text("Kitchenware")
      expect(move.categories.reload.pluck(:name)).to include("Kitchenware")
    end

    it "renames a category and the rename propagates" do
      category = create(:category, move:, name: "Bookz")

      visit move_vocabularies_path(move, "categories", edit: category.id)
      within "#vocab-#{category.id}" do
        fill_in "vocabulary[name]", with: "Books"
        click_button I18n.t("vocabularies.form.save"), exact: true
      end

      expect(category.reload.name).to eq("Books")
      expect(page).to have_text("Books")
    end

    it "adds a tag with an applies-to facet" do
      visit move_vocabularies_path(move, "tags")

      fill_in "vocabulary[name]", with: "Fragile"
      select I18n.t("vocabularies.applies_to.box"), from: "vocabulary[applies_to]"
      click_button I18n.t("vocabularies.form.add_submit"), exact: true

      expect(move.tags.find_by(name: "Fragile").applies_to).to eq("box")
      expect(page).to have_text("Fragile")
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
      create(:move_membership, move:, user: member, role: "member")
      login_as(user: member)
    end

    it "views the list read-only with no add affordance" do
      create(:category, move:, name: "Kitchenware")

      visit move_vocabularies_path(move, "categories")

      expect(page).to have_text("Kitchenware")
      expect(page).to have_no_text(I18n.t("vocabularies.categories.add"))
      expect(page).to have_no_button(I18n.t("vocabularies.form.add_submit"))
    end
  end
end
