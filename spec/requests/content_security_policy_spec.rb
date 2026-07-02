# frozen_string_literal: true

require "rails_helper"

# #493 — the app ships a Content-Security-Policy (report-only initially). script-src
# stays strict (self + nonce, no unsafe-inline) as the XSS backstop; style-src allows
# unsafe-inline for the UI's inline style="…" attributes.
RSpec.describe "Content Security Policy" do
  subject(:header) { response.headers["Content-Security-Policy-Report-Only"] }

  before { get "/" }

  it "sends the policy report-only (not enforcing) during rollout" do
    expect(header).to be_present
    expect(response.headers["Content-Security-Policy"]).to be_nil
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
end
