# frozen_string_literal: true

require "base64"

module ImageProviders
  # OpenAI image generation (Images API). Reuses the Move's encrypted
  # openai_api_key — the same key recognition/embeddings use. Returns the decoded
  # PNG bytes; gpt-image-1 always responds with base64 image data.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/images/generations"
    DEFAULT_MODEL = "gpt-image-1"
    SIZE = "1024x1024"

    def generate(prompt:)
      key = api_key!
      data = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{key}" },
        body: { model: model, prompt: prompt, n: 1, size: SIZE },
        read_timeout: 120 # image generation is slower than a chat completion
      )
      Result.new(provider: "openai", model: model, image_bytes: decode(data), content_type: "image/png")
    end

    private

    def decode(data)
      b64 = data.is_a?(Hash) ? data.dig("data", 0, "b64_json") : nil
      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with no image data" if b64.blank?

      Base64.strict_decode64(b64)
    rescue ArgumentError
      # Present but malformed base64 — surface as a provider failure so the action's
      # ProviderHttp::Error rescue runs (releases the claim, reverts the card)
      # rather than escaping as an uncaught ArgumentError (#416 Codex).
      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with undecodable image data"
    end
  end
end
