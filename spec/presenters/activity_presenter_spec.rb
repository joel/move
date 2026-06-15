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
end
