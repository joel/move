# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Post permissions" do
  it "hides post actions when signed out" do
    post = create(:post)

    visit posts_path
    expect(page).to have_no_link("New post")
    expect(page).to have_no_link("Edit")

    visit post_path(post)
    expect(page).to have_no_link("Edit post")
    expect(page).to have_no_button("Delete")
  end

  it "shows edit and delete only for the owner" do
    owner = create(:user)
    other = create(:user)
    owned_post = create(:post, user: owner)
    other_post = create(:post, user: other)

    login_as(user: owner)

    visit posts_path
    within("[id='post_#{owned_post.id}']") do
      expect(page).to have_link("Edit")
    end
    within("[id='post_#{other_post.id}']") do
      expect(page).to have_no_link("Edit")
    end

    visit post_path(owned_post)
    expect(page).to have_link("Edit post")
    expect(page).to have_button("Delete")

    visit post_path(other_post)
    expect(page).to have_no_link("Edit post")
    expect(page).to have_no_button("Delete")
  end

  it "shows edit and delete for admins" do
    admin = create(:user, :admin)
    other = create(:user)
    post = create(:post, user: other)

    login_as(user: admin)

    visit post_path(post)
    expect(page).to have_link("Edit post")
    expect(page).to have_button("Delete")
  end
end
