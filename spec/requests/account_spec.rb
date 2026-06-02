# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/account" do
  let(:user) { create(:user, name: "Original Name") }

  before { stub_current_user(user) }

  it "renders the account page" do
    get account_url
    expect(response).to be_successful
  end

  it "renders the edit account page" do
    get edit_account_url
    expect(response).to be_successful
  end

  it "updates the account name" do
    patch account_url, params: { user: { name: "Updated Name", email: "ignored@example.com" } }
    expect(response).to redirect_to(account_url)
    user.reload
    expect(user.name).to eq("Updated Name")
    expect(user.email).not_to eq("ignored@example.com")
  end

  it "deletes the account" do
    expect do
      delete account_url
    end.to change(User, :count).by(-1)
    expect(response).to redirect_to(root_url)
  end

  it "requires authentication" do
    stub_current_user(nil)
    get account_url
    expect(response).to have_http_status(:unauthorized)
  end
end
