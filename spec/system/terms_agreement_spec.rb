# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Terms agreement gate" do
  let(:user) { create(:user) }

  before { stub_current_tenant("acme") }

  it "walls off the app until the account accepts, then lets them in" do
    login_as(user:, accept_terms: false)

    visit moves_path
    expect(page).to have_current_path(agreement_path, ignore_query: true)
    expect(page).to have_text(Terms::TITLE)

    click_button "Accept & continue"

    expect(page).to have_current_path(moves_path, ignore_query: true)
    expect(user.terms_acceptances.where(terms_version: Terms::CURRENT_VERSION)).to exist
  end

  it "lets an account that has already accepted straight into the app" do
    login_as(user:) # accepts by default

    visit moves_path

    expect(page).to have_current_path(moves_path, ignore_query: true)
    expect(page).to have_no_text(Terms::TITLE)
  end
end
