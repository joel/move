# frozen_string_literal: true

# Provider-agnostic image recognition (Domain §6, Technical Foundation §10).
# Domain code talks to RecognitionProviders, never to a vendor API directly. The
# selected adapter returns a normalized RecognitionProviders::Result.
module RecognitionProviders
  module_function

  # Resolve the configured adapter instance. `RECOGNITION_PROVIDER` (or the
  # config.x default) selects fake/openai/anthropic; unknown falls back to fake.
  def resolve(name = configured_name)
    case name.to_s
    when "openai" then Openai.new
    when "anthropic" then Anthropic.new
    else Fake.new
    end
  end

  def configured_name
    ENV["RECOGNITION_PROVIDER"].presence ||
      Rails.application.config.x.recognition_provider.presence ||
      "fake"
  end
end
