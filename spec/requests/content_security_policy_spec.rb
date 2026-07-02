# frozen_string_literal: true

require "rails_helper"

# #493 — the app ships an ENFORCING Content-Security-Policy (rolled out report-only
# first; flipped after prod was confirmed violation-free). script-src stays strict
# (self + nonce, no unsafe-inline) as the XSS backstop; style-src allows
# unsafe-inline for the UI's inline style="…" attributes.
RSpec.describe "Content Security Policy" do
  subject(:header) { response.headers["Content-Security-Policy"] }

  before { get "/" }

  it "enforces the policy (report-only rollout complete — #493)" do
    expect(header).to be_present
    expect(response.headers["Content-Security-Policy-Report-Only"]).to be_nil
  end

  it "keeps script-src strict: self + a non-empty nonce, and no unsafe-inline" do
    expect(header).to match(/script-src [^;]*'self'/)
    # Non-empty nonce — `session.id` is blank pre-session and would emit `'nonce-'`.
    expect(header).to match(%r{script-src [^;]*'nonce-[\w+/=]{8,}'})
    expect(header).not_to match(/script-src [^;]*'unsafe-inline'/)
  end

  it "locks down object-src, base-uri, and frame-ancestors" do
    expect(header).to include("object-src 'none'")
    expect(header).to include("base-uri 'self'")
    expect(header).to include("frame-ancestors 'none'")
  end

  it "allows inline style attributes (progress bars, display toggles)" do
    expect(header).to match(/style-src [^;]*'unsafe-inline'/)
  end

  it "names a wss origin in connect-src for ActionCable (:self is not honoured for ws)" do
    expect(header).to match(/connect-src [^;]*wss/)
  end

  it "points report-uri at the collection endpoint" do
    expect(header).to include("report-uri /csp-violation-report")
  end

  describe "POST /csp-violation-report (the report sink)" do
    it "accepts a violation report and returns 204" do
      body = { "csp-report" => { "violated-directive" => "script-src", "blocked-uri" => "inline" } }
      post "/csp-violation-report", params: body.to_json, headers: { "Content-Type" => "application/csp-report" }
      expect(response).to have_http_status(:no_content)
    end

    it "does not raise on a malformed body" do
      post "/csp-violation-report", params: "}{ not json", headers: { "Content-Type" => "application/csp-report" }
      expect(response).to have_http_status(:no_content)
    end

    it "redacts token-bearing query strings from the logged summary" do
      allow(Rails.logger).to receive(:warn)
      body = { "csp-report" => { "violated-directive" => "script-src",
                                 "document-uri" => "https://move.move-easy.docker/email-auth?key=SUPERSECRET" } }
      post "/csp-violation-report", params: body.to_json, headers: { "Content-Type" => "application/csp-report" }

      expect(Rails.logger).to have_received(:warn).with(
        satisfy { |m| m.include?("/email-auth") && m.exclude?("SUPERSECRET") }
      )
    end
  end
end
