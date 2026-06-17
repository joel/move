# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingProviders do
  describe ".for_move" do
    it "returns the openai adapter when the Move is embedding-ready" do
      move = instance_double(Move, embedding_provider_ready?: true, openai_api_key: "sk-move")

      expect(described_class.for_move(move)).to be_a(EmbeddingProviders::Openai)
    end

    it "returns the fake adapter when the Move is not embedding-ready (openai without a key, or fake)" do
      move = instance_double(Move, embedding_provider_ready?: false, openai_api_key: nil)

      expect(described_class.for_move(move)).to be_a(EmbeddingProviders::Fake)
    end

    it "returns the fake adapter for a nil move" do
      expect(described_class.for_move(nil)).to be_a(EmbeddingProviders::Fake)
    end
  end

  describe EmbeddingProviders::Fake do
    subject(:provider) { described_class.new }

    def cosine(vec_a, vec_b)
      dot = vec_a.zip(vec_b).sum { |x, y| x * y }
      dot / (Math.sqrt(vec_a.sum { |x| x**2 }) * Math.sqrt(vec_b.sum { |x| x**2 }))
    end

    it "produces a deterministic, L2-normalized 1536-dim vector" do
      a = provider.embed("hair dryer").vector
      b = provider.embed("hair dryer").vector
      expect(a).to eq(b)
      expect(a.size).to eq(1536)
      expect(Math.sqrt(a.sum { |x| x**2 })).to be_within(0.0001).of(1.0)
    end

    it "scores shared-token texts more similar than unrelated ones" do
      query = provider.embed("blow dryer").vector
      related = provider.embed("hair dryer").vector # shares "dryer"
      unrelated = provider.embed("cast iron skillet").vector

      expect(cosine(query, related)).to be > cosine(query, unrelated)
    end

    it "returns a nil vector for blank text" do
      expect(provider.embed("   ").vector).to be_nil
    end
  end

  describe EmbeddingProviders::Openai do
    subject(:provider) { described_class.new(api_key: "sk-test") }

    def stub_http(code:, body:)
      response = instance_double(Net::HTTPResponse, code: code, body: body)
      allow(Net::HTTP).to receive(:start).and_return(response)
    end

    it "raises MissingApiKey when built without the Move's key" do
      expect { described_class.new.embed("x") }
        .to raise_error(EmbeddingProviders::Base::MissingApiKey)
    end

    it "returns a blank result for blank text without calling the API" do
      expect(provider.embed("").vector).to be_nil
    end

    it "returns the embedding vector on a 2xx response" do
      stub_http(code: "200", body: { data: [{ embedding: [0.1, 0.2, 0.3] }] }.to_json)

      result = provider.embed("hair dryer")

      expect(result.provider).to eq("openai")
      expect(result.vector).to eq([0.1, 0.2, 0.3])
      expect(result.model).to eq("text-embedding-3-small")
    end

    it "raises on a non-2xx response, surfacing the status and vendor message" do
      stub_http(code: "429", body: { error: { message: "Rate limit reached" } }.to_json)

      expect { provider.embed("hair dryer") }
        .to raise_error(ProviderHttp::Error, /429.*Rate limit reached/)
    end

    it "raises when a 2xx response carries no embedding" do
      stub_http(code: "200", body: { data: [] }.to_json)

      expect { provider.embed("hair dryer") }.to raise_error(ProviderHttp::Error, /missing data/)
    end
  end
end
