# frozen_string_literal: true

require "rails_helper"

RSpec.describe RodauthMain do
  # tenant_handoff_url is the apex's post-auth landing builder (#280): it mints a
  # single-use handoff token and, on success, clears the apex session (the apex is
  # a pure broker). Exercised on an allocated Rodauth instance with account_id
  # stubbed; clear_session is set up as a spy (it needs no real request context
  # here — on the failure path it must NOT be called, #349).
  describe "#tenant_handoff_url" do
    let(:rodauth) { RodauthApp.rodauth(nil).allocate }
    let(:user) { create(:user, status: 2) }

    before do
      allow(rodauth).to receive(:account_id).and_return(user.id)
      allow(rodauth).to receive(:clear_session)
    end

    it "mints a single-use handoff URL and clears the apex session on success" do
      url = rodauth.tenant_handoff_url("demo")

      expect(url).to start_with("https://demo.").and include("/session/handoff?token=")
      expect(rodauth).to have_received(:clear_session)
      expect(SessionHandoffToken.where(user_id: user.id, organization_slug: "demo")).to exist
    end

    context "when the token cannot be minted (#349)" do
      before do
        failed = instance_double(SessionHandoffs::Mint, call: Dry::Monads::Failure(:boom))
        allow(SessionHandoffs::Mint).to receive(:new).and_return(failed)
      end

      it "stays on the apex root and does NOT clear the apex session" do
        expect(rodauth.tenant_handoff_url("demo")).to eq("/")
        expect(rodauth).not_to have_received(:clear_session)
        expect(SessionHandoffToken.count).to eq(0)
      end
    end

    context "when the account no longer exists" do
      before { allow(rodauth).to receive(:account_id).and_return(SecureRandom.uuid) }

      it "stays on the apex root without raising or clearing the session" do
        expect(rodauth.tenant_handoff_url("demo")).to eq("/")
        expect(rodauth).not_to have_received(:clear_session)
      end
    end

    context "when the token insert raises a DB error (#351)" do
      before do
        allow(SessionHandoffToken).to receive(:create!)
          .and_raise(ActiveRecord::StatementInvalid.new("PG::ConnectionBad"))
      end

      it "stays on the apex root without 500-ing the post-auth redirect" do
        url = nil
        expect { url = rodauth.tenant_handoff_url("demo") }.not_to raise_error
        expect(url).to eq("/")
        expect(rodauth).not_to have_received(:clear_session)
      end
    end
  end
end
