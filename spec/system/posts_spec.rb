# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Posts" do
  let!(:user) { create(:user) }

  it "allows a user to create a new post" do
    # Visit the page where the user can create a post
    visit new_post_path

    # Fill in the form fields
    fill_in "Title", with: "My First Post"
    fill_in "Body", with: "This is the body of my first post."

    # Submit the form
    click_on "Create Post"

    # Expect to see the success message or be redirected to the post show page
    expect(page).to have_text("Post was successfully created")

    # Optionally, you can check that the title and body are displayed on the page
    expect(page).to have_text("My First Post")
    expect(page).to have_text("This is the body of my first post.")
  end

  it "shows error messages when the form is submitted without a title or body" do
    # Visit the new post page
    visit new_post_path

    fill_in "Title", with: ""

    # Leave the form fields blank and submit the form
    click_on "Create Post"

    # Expect to see validation error messages
    expect(page).to have_text("Title can't be blank")
  end
end
