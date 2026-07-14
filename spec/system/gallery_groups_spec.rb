# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Gallery Groups" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  # Member ordering and singleton exclusion are pinned by the request specs;
  # this walks the click path a user takes to find their scattered batteries.
  it "browses a scattered family end to end: toggle → card → checklist → box" do
    box_two = create(:box, move:, number: "2", room: create(:room, move:, name: "Kitchen"))
    box_ten = create(:box, move:, number: "10")
    create(:item, :auto_confirmed, move:, box: box_two, name: "AA batteries")
    create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA batteries")
    Clusters::Recompute.new.call(move:)

    visit move_gallery_path(move)
    click_on I18n.t("galleries.toggle.groups")

    expect(page).to have_text(I18n.t("galleries.groups.subtitle"))
    expect(page).to have_text("2 items").and have_text("2 boxes")
    expect(page).to have_text("Box 2").and have_text("Box 10")

    click_on move.item_clusters.sole.label
    expect(page).to have_text("AA batteries").and have_text("Box 2 · Kitchen")

    page.find("a[href='#{move_box_path(move, box_two)}']").click
    expect(page).to have_current_path(move_box_path(move, box_two))
  end

  it "walks the pre-compute journey: organizing state, then groups after the recompute" do
    box = create(:box, move:, number: "1")
    2.times { create(:item, :auto_confirmed, move:, box:, name: "AA batteries") }
    configured = instance_double(ActiveJob::ConfiguredJob, perform_later: nil)
    allow(Clusters::RefreshJob).to receive(:set).and_return(configured)

    visit move_gallery_path(move, view: "groups")
    expect(page).to have_text(I18n.t("galleries.groups.organizing.title"))

    Clusters::Recompute.new.call(move:) # what the debounced job will do
    visit move_gallery_path(move, view: "groups")

    expect(page).to have_text("AA batteries")
    expect(page).to have_text("2 items")
  end
end
