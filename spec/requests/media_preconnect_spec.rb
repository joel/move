# frozen_string_literal: true

require "rails_helper"

# #671: the layout head must pre-establish the cross-origin connection to the
# media transform host so the first image of a cold page load skips DNS + TCP +
# TLS (~200ms measured in the #664 baseline). No hint when no host is
# configured — dev/test serve media same-origin.
RSpec.describe "Media host preconnect" do
  let(:user) { create(:user) }

  before { stub_current_user(user) }

  context "when MEDIA_TRANSFORM_HOST is configured (prod-like)" do
    around do |example|
      original = Rails.application.config.x.media_transform_host
      Rails.application.config.x.media_transform_host = "media.example.org"
      example.run
      Rails.application.config.x.media_transform_host = original
    end

    it "emits preconnect + dns-prefetch hints for the media host" do
      get account_url
      expect(response.body).to include('<link rel="preconnect" href="https://media.example.org">')
      expect(response.body).to include('<link rel="dns-prefetch" href="https://media.example.org">')
    end
  end

  context "when MEDIA_TRANSFORM_HOST is unset (dev/test default)" do
    it "renders no media resource hints" do
      get account_url
      expect(response).to be_successful
      expect(response.body).not_to include('rel="preconnect"')
      expect(response.body).not_to include('rel="dns-prefetch"')
    end
  end
end
