# frozen_string_literal: true

require "rails_helper"

# D14 (#608) — the Google button must forward a Move invitation token through
# the OmniAuth round-trip (same channel as #346's `org`), or a Google-auth
# invitee drops the token, gets a stray personal org, and misses the accept
# landing. `omniauth_forward_params` is the source of those query params.
RSpec.describe Components::GoogleAuthButton do
  def forward_params_for(params)
    button = described_class.new
    view = instance_double(ActionView::Base, params: ActionController::Parameters.new(params))
    button.instance_variable_set(:@_view_context, view)
    allow(button).to receive(:view_context).and_return(view)
    button.send(:omniauth_forward_params)
  end

  it "forwards a present invite token (and org) into the OmniAuth request" do
    expect(forward_params_for(org: "acme", invite_token: "tok-abc"))
      .to eq(org: "acme", invite_token: "tok-abc")
  end

  it "omits absent or blank params" do
    expect(forward_params_for(invite_token: "tok-abc")).to eq(invite_token: "tok-abc")
    expect(forward_params_for(org: "", invite_token: "")).to eq({})
    expect(forward_params_for({})).to eq({})
  end
end
