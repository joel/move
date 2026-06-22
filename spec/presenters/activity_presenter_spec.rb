# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityPresenter do
  # predicate only reads action + metadata, so an unsaved Activity is enough.
  def predicate_for(action, metadata)
    activity = Activity.new(action:, metadata:, occurred_at: Time.current)
    described_class.new(activity, actors: {}, subjects: {}, current_user_id: nil).predicate
  end

  it "interpolates the provider into a provider-change summary (#187 regression)" do
    expect(predicate_for("move.recognition_provider_changed", { "provider" => "openai" }))
      .to eq("switched the AI provider to openai")
  end

  it "interpolates provider and model into a model-change summary (#187)" do
    expect(predicate_for("move.recognition_model_changed", { "provider" => "openai", "model" => "gpt-5" }))
      .to eq("set the openai model to gpt-5")
  end

  it "renders the new AI Capability key events (#242)" do
    expect(predicate_for("move.provider_key_set", { "provider" => "voyage" })).to eq("added the voyage API key")
    expect(predicate_for("move.provider_key_removed", { "provider" => "gemini" })).to eq("removed the gemini API key")
  end

  it "interpolates the count into a labels-per-box summary (#310)" do
    expect(predicate_for("move.labels_per_box_changed", { "labels_per_box" => 5 }))
      .to eq("set labels per box to 5")
  end

  it "still renders historical rows recorded under the legacy key-removed action (#242)" do
    expect(predicate_for("move.recognition_key_removed", { "provider" => "openai" }))
      .to eq("removed the openai API key")
  end
end
