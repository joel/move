# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Insurance exports" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    box = create(:box, move:, number: "1", room: create(:room, move:))
    create(:item, :manual, move:, box:, name: "Espresso Machine")
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "reaches Insurance from the Menu and renders both cards for an admin" do
    visit move_menu_path(move)
    expect(page).to have_link(I18n.t("menu.show.insurance"), href: move_insurance_path(move))

    click_on I18n.t("menu.show.insurance")

    aggregate_failures do
      expect(page).to have_current_path(move_insurance_path(move), ignore_query: true)
      expect(page).to have_text(I18n.t("insurance.declaration.title"))
      expect(page).to have_text(I18n.t("insurance.dossier.title"))
      # The declaration link must bypass Turbo (it returns a PDF, not HTML);
      # don't click PDF links under rack_test — byte assertions live in the
      # request specs.
      expect(page).to have_css(
        "a[href='#{move_insurance_declaration_path(move)}'][data-turbo='false']"
      )
    end
  end

  it "generates a dossier and lands on the progress page with a download" do
    # :inline queue adapter → GenerateJob runs during the POST, so by the time
    # the redirect lands the run is completed and the Download is shown.
    visit move_insurance_path(move)
    click_on I18n.t("insurance.dossier.generate")

    run = move.insurance_dossier_runs.last
    aggregate_failures do
      expect(page).to have_current_path(move_insurance_dossier_run_path(move, run), ignore_query: true)
      expect(page).to have_text(I18n.t("insurance.run.title"))
      expect(page).to have_link(I18n.t("insurance.status.download"))
      expect(run).to be_ready
    end
  end

  it "hides the dossier card from a contributor while keeping the declaration" do
    contributor = create(:user)
    create(:move_membership, move:, user: contributor, role: "contributor")
    login_as(user: contributor)

    visit move_insurance_path(move)

    expect(page).to have_text(I18n.t("insurance.declaration.title"))
    expect(page).to have_no_text(I18n.t("insurance.dossier.title"))
  end
end
