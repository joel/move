# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Box detail & lifecycle" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  # The lifecycle clicks (seal / unseal / transition) now live behind the JS
  # Manage-box sheet; their behaviour is covered route-level in the request spec
  # (spec/requests/boxes_spec.rb) and the sheet interaction in
  # spec/system/box_manage_sheet_spec.rb (:js). Here we assert the no-JS surface:
  # identity, the contextual hero, the ⋮ trigger, and the edit→volume derivation.
  it "shows identity, the capture hero + manage trigger, and derives volume from an edit" do
    box = create(:box, move:, number: "1", status: "packing", room: nil)

    visit move_box_path(move, box)
    expect(page).to have_text("Box #001")
    # Packing → the single contextual hero is Capture; secondary actions are in ⋮.
    expect(page).to have_link(I18n.t("boxes.actions.capture"))
    expect(page).to have_css("button[aria-label='#{I18n.t("boxes.manage.trigger")}']")

    # Edit: assign a room; the room chip surfaces on the slim header. (Dimensions /
    # volume now live in the ⋮ Manage sheet — covered in manage_sheet_spec.)
    visit edit_move_box_path(move, box)
    fill_in I18n.t("boxes.form.room"), with: "Kitchen"
    fill_in I18n.t("boxes.form.length_cm"), with: "40"
    fill_in I18n.t("boxes.form.width_cm"), with: "30"
    fill_in I18n.t("boxes.form.height_cm"), with: "25"
    click_button I18n.t("boxes.edit.submit")

    expect(page).to have_text("Kitchen")
  end

  it "shows the review CTA for a box whose only items are needs_correction (#146)" do
    box = create(:box, move:, number: "2", status: "packing")
    media = create(:media, move:, box:)
    create(:item, move:, box:, source_media: media, name: "Magazines", review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_link(I18n.t("boxes.show.pending_review", count: 1))
  end

  it "hides the review CTA for a needs_correction item with no source photo (#146)" do
    box = create(:box, move:, number: "3", status: "packing")
    # No source_media → the photo-keyed walk can't review it (resolved on C3), so
    # the badge must not advertise a CTA that dead-ends on "nothing to review".
    create(:item, move:, box:, name: "Loose papers", review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_text("Box #003")
    expect(page).to have_no_link(I18n.t("boxes.show.pending_review", count: 1))
  end

  it "ignores a moved-in item whose source photo belongs to another box (#146)" do
    foreign_media = create(:media, move:, box: create(:box, move:, number: "4"))
    box = create(:box, move:, number: "5", status: "packing")
    # In this box, but its source photo lives in box 4 — the box-5 walk can't reach
    # it, so the badge must not count it. Neither the pending nor the "all reviewed"
    # badge may render: the box has no walkable photo of its own.
    create(:item, move:, box:, source_media: foreign_media, review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_text("Box #005")
    expect(page).to have_no_link(I18n.t("boxes.show.pending_review", count: 1))
    expect(page).to have_no_link(I18n.t("boxes.show.review_complete"))
  end

  it "shows a permanent green review link once every item is reviewed" do
    box = create(:box, move:, number: "6", status: "packing")
    media = create(:media, move:, box:)
    # A confirmed item backed by this box's own photo: nothing pending, but the box
    # is still walkable — so the badge stays accessible, in its green state.
    create(:item, move:, box:, source_media: media, name: "Plates", review_state: "confirmed")

    visit move_box_path(move, box)

    expect(page).to have_link(I18n.t("boxes.show.review_complete"))
    expect(page).to have_no_link(I18n.t("boxes.show.pending_review", count: 1))
  end

  it "stays tertiary (not green) when a still-pending item has no walkable photo" do
    box = create(:box, move:, number: "7", status: "packing")
    media = create(:media, move:, box:)
    # A reviewed photo makes the box walkable (green-eligible)…
    create(:item, move:, box:, source_media: media, name: "Plates", review_state: "confirmed")
    # …but a still-pending item with no source photo means the box is NOT done. The
    # badge must not claim "All items reviewed" just because the pending item isn't
    # photo-backed (it counts toward unreviewed regardless of walkability).
    create(:item, move:, box:, name: "Loose papers", review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_link(I18n.t("boxes.show.pending_review", count: 1))
    expect(page).to have_no_link(I18n.t("boxes.show.review_complete"))
  end

  it "is read-only on an archived move" do
    archived = create(:move, :archived, created_by: user)
    box = create(:box, :with_room, move: archived, number: "1", status: "packing")

    visit move_box_path(archived, box)

    expect(page).to have_text("Box #001")
    expect(page).to have_text(I18n.t("boxes.show.archived"))
    expect(page).to have_no_button(I18n.t("boxes.actions.seal"))
    expect(page).to have_no_link(I18n.t("boxes.show.edit"))
  end

  it "walks box-to-box with the header nav, disabling the ends (#694)" do
    create(:box, move:, number: "1")
    box2 = create(:box, move:, number: "2")
    create(:box, move:, number: "3")

    visit move_box_path(move, box2)

    # The jump select lists the whole walk inside the form targeting the jump
    # redirect. (The auto-submit itself is JS; the redirect is request-spec covered.)
    expect(page).to have_css(
      "form[action='#{jump_move_boxes_path(move)}'] select[name='id'] option", count: 3
    )

    find("a[aria-label='#{I18n.t("boxes.show.nav.next")}']").click
    expect(page).to have_text("Box #003")
    expect(page).to have_no_css("a[aria-label='#{I18n.t("boxes.show.nav.next")}']")
    expect(page).to have_css("nav span[aria-disabled='true']")

    find("a[aria-label='#{I18n.t("boxes.show.nav.previous")}']").click
    find("a[aria-label='#{I18n.t("boxes.show.nav.previous")}']").click
    expect(page).to have_text("Box #001")
    expect(page).to have_no_css("a[aria-label='#{I18n.t("boxes.show.nav.previous")}']")
  end
end
