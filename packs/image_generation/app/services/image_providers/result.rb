# frozen_string_literal: true

module ImageProviders
  # The vendor-independent result returned by every adapter — `provider`/`model`
  # are labels only; `image_bytes` is the raw generated image and `content_type`
  # its MIME type, ready to attach to a Media via ActiveStorage.
  Result = Data.define(:provider, :model, :image_bytes, :content_type)
end
