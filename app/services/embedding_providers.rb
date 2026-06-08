# frozen_string_literal: true

# Provider-agnostic text embeddings for D8 hybrid search (Domain §7.3 / §7.5;
# Technical Foundation §11.4). Domain code asks EmbeddingProviders for a vector;
# the selected adapter returns a normalized EmbeddingProviders::Result. Only
# textual metadata is ever embedded — raw images never are (Domain §7.5).
module EmbeddingProviders
  module_function

  # `EMBEDDING_PROVIDER` (or the config.x default) selects fake/openai; unknown
  # falls back to the deterministic, network-free fake.
  def resolve(name = configured_name)
    case name.to_s
    when "openai" then Openai.new
    else Fake.new
    end
  end

  def configured_name
    ENV["EMBEDDING_PROVIDER"].presence ||
      Rails.application.config.x.embedding_provider.presence ||
      "fake"
  end
end
