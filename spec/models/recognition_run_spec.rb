# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionRun do
  def run_with(message)
    build(:recognition_run, :failed, error_message: message)
  end

  describe "#error_category" do
    it "classifies an exhausted quota / billing message as :quota" do
      expect(run_with("(429): You exceeded your current quota, please check your plan and billing details.")
        .error_category).to eq(:quota)
      expect(run_with("Your credit balance is too low to access the Anthropic API.")
        .error_category).to eq(:quota)
    end

    it "prefers :quota over :rate_limit when a quota error arrives as HTTP 429" do
      expect(run_with("request failed (429): insufficient_quota").error_category).to eq(:quota)
    end

    it "classifies a plain rate-limit message as :rate_limit" do
      expect(run_with("request failed (429): Rate limit reached").error_category).to eq(:rate_limit)
    end

    it "classifies an auth/key message as :auth" do
      expect(run_with("request failed (401): invalid x-api-key").error_category).to eq(:auth)
    end

    it "classifies a transport failure as :network" do
      expect(run_with("Net::OpenTimeout: execution expired").error_category).to eq(:network)
    end

    it "falls back to :generic for anything unrecognized" do
      expect(run_with("The model glitched.").error_category).to eq(:generic)
      expect(run_with(nil).error_category).to eq(:generic)
    end
  end

  describe "#error_detail" do
    it "strips the internal transport prefix" do
      expect(run_with("RecognitionProviders::Openai request failed (500): The model glitched.")
        .error_detail).to eq("The model glitched.")
    end

    it "returns the message unchanged when there is no prefix" do
      expect(run_with("Provider unavailable").error_detail).to eq("Provider unavailable")
    end

    it "returns nil when blank" do
      expect(run_with(nil).error_detail).to be_nil
      expect(run_with("").error_detail).to be_nil
    end
  end
end
