# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingProviders do
  describe ".resolve" do
    it "returns the fake provider by default and for unknown names" do
      expect(described_class.resolve("fake")).to be_a(EmbeddingProviders::Fake)
      expect(described_class.resolve("bogus")).to be_a(EmbeddingProviders::Fake)
    end

    it "returns the openai provider when selected" do
      expect(described_class.resolve("openai")).to be_a(EmbeddingProviders::Openai)
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
    subject(:provider) { described_class.new }

    def stub_http(code:, body:)
      response = instance_double(Net::HTTPResponse, code: code, body: body)
      allow(Net::HTTP).to receive(:start).and_return(response)
    end

    it "raises without an API key" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
      expect { provider.embed("x") }.to raise_error(/OPENAI_API_KEY/)
    end

    it "returns a blank result for blank text without calling the API" do
      expect(provider.embed("").vector).to be_nil
    end

    context "with an API key" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
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
end
