# frozen_string_literal: true

require "rails_helper"

# #492 â passwordless auth secrets must be redacted from logs. Rails builds its
# request-path/params log filter from `config.filter_parameters` via
# ActiveSupport::ParameterFilter, so asserting the filter redacts these keys
# proves the log output does too.
RSpec.describe "log parameter filtering" do # rubocop:disable RSpec/DescribeClass
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "redacts the Rodauth email-auth / verify-account `key` param" do
    expect(filter.filter("key" => "magic-link-secret")).to eq("key" => "[FILTERED]")
  end

  it "redacts the Google One Tap `credential` (ID token)" do
    expect(filter.filter("credential" => "eyJhbGciOiJSUzI1NiIsImtpZCI6...")).to eq(
      "credential" => "[FILTERED]"
    )
  end

  it "redacts Active Storage signed ids (blob-read capability — MCP upload params, #531)" do
    expect(filter.filter("signed_id" => "eyJfcmFpbHMi...")).to eq("signed_id" => "[FILTERED]")
  end

  it "still redacts provider API keys, tokens, and passwords" do
    filtered = filter.filter(
      "openai_api_key" => "sk-secret", "token" => "t", "password" => "p"
    )
    expect(filtered).to eq(
      "openai_api_key" => "[FILTERED]", "token" => "[FILTERED]", "password" => "[FILTERED]"
    )
  end
end
