# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveMcp::Tools::Base do
  describe ".failure_response" do
    it "maps a known failure to its copy" do
      response = described_class.failure_response(:move_archived)

      expect(response.content.first[:text]).to eq("This move is archived and is read-only.")
    end

    it "falls back to generic copy for an unmapped failure, never the raw symbol (#972)" do
      response = described_class.failure_response(:some_new_reason)

      aggregate_failures do
        expect(response.error?).to be(true)
        expect(response.content.first[:text]).to eq("That action could not be completed.")
      end
    end
  end
end
