# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/account" do
  let(:user) { create(:user, name: "Original Name") }

  before { stub_current_user(user) }

  it "renders the account page with the inline rename form and danger zone" do
    get account_url
    expect(response).to be_successful
    expect(response.body).to include("Danger zone")
    expect(response.body).to include("inline-edit") # rename toggle controller
    expect(response.body).to include('aria-label="Edit name"')
    expect(response.body).to include('aria-label="Account name"') # labelled inline field
  end

  it "submits the delete form natively (turbo:false) with a Stimulus confirm" do
    # Deletion ends in a cross-host redirect Turbo won't follow; the form must
    # submit natively and confirm via the `confirm` controller, not turbo-confirm.
    get account_url
    expect(response.body).to include('data-turbo="false"')
    expect(response.body).to include('data-controller="confirm"')
    expect(response.body).to include("submit-&gt;confirm#confirm")
  end

  it "no longer exposes a separate edit route" do
    expect { edit_account_path }.to raise_error(NameError)
  end

  it "updates the account name" do
    patch account_url, params: { user: { name: "Updated Name", email: "ignored@example.com" } }
    expect(response).to redirect_to(account_url)
    user.reload
    expect(user.name).to eq("Updated Name")
    expect(user.email).not_to eq("ignored@example.com")
  end

  it "deletes the account, its organization membership and tenant" do
    # Reproduces the production 500: the organization_memberships FK has no
    # ON DELETE CASCADE, so a bare users DELETE was rejected (#fk_rails_57cf70d280).
    organization = create(:organization, slug: "acme")
    create(:organization_membership, :owner, organization: organization, user: user)
    allow(Apartment::Tenant).to receive(:drop)
    allow(Apartment::Tenant).to receive(:switch).and_yield
    allow(ActiveRecord::Base.connection).to receive(:schema_exists?).and_call_original
    allow(ActiveRecord::Base.connection).to receive(:schema_exists?).with("acme").and_return(true)

    expect do
      delete account_url
    end.to change(User, :count).by(-1)
       .and change(Organization, :count).by(-1)

    # Redirects to the canonical apex root, never the just-dropped subdomain.
    apex = Rails.application.config.action_mailer.default_url_options.fetch(:host)
    expect(response).to redirect_to(root_url(host: apex))
    expect(Apartment::Tenant).to have_received(:drop).with("acme")
  end

  it "redirects a failed delete to the apex when the current subdomain was dropped" do
    # Simulate a partial multi-org teardown: the action fails after the current
    # subdomain's tenant was already dropped, so a same-host redirect would 404.
    failing = instance_double(Accounts::Delete,
                              call: Dry::Monads::Result::Failure.new(:tenant_drop_failed))
    allow(Accounts::Delete).to receive(:new).and_return(failing)
    stub_current_tenant("gone-org") # current subdomain, no Organization row

    delete account_url

    apex = Rails.application.config.action_mailer.default_url_options.fetch(:host)
    expect(response).to redirect_to(root_url(host: apex))
  end

  it "requires authentication" do
    stub_current_user(nil)
    get account_url
    expect(response).to have_http_status(:unauthorized)
  end
end
