# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingProviders do
  describe ".for_move" do
    def ready_move(provider, key)
      instance_double(
        Move, embedding_provider_ready?: true, embedding_provider: provider,
              embedding_api_key_for: key
      )
    end

    it "returns the openai adapter when openai is selected and ready" do
      expect(described_class.for_move(ready_move("openai", "sk-move")))
        .to be_a(EmbeddingProviders::Openai)
    end

    it "returns the gemini adapter when gemini is selected and ready" do
      expect(described_class.for_move(ready_move("gemini", "gk-move")))
        .to be_a(EmbeddingProviders::Gemini)
    end

    it "returns the voyage adapter when voyage is selected and ready" do
      expect(described_class.for_move(ready_move("voyage", "vk-move")))
        .to be_a(EmbeddingProviders::Voyage)
    end

    it "returns the fake adapter when the Move is not embedding-ready (real provider without a key, or fake)" do
      move = instance_double(Move, embedding_provider_ready?: false)

      expect(described_class.for_move(move)).to be_a(EmbeddingProviders::Fake)
    end

    it "returns the fake adapter for a nil move" do
      expect(described_class.for_move(nil)).to be_a(EmbeddingProviders::Fake)
    end
  end

  describe ".resolve" do
    it "falls back to the keyless Fake adapter for an unknown provider name" do
      expect(described_class.resolve("nope", api_key: "x")).to be_a(EmbeddingProviders::Fake)
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

  # Shared expectations for the real BYO adapters that conform their native vector
  # to the fixed 1536-d column via Base#fit_dimensions (#237).
  def stub_http(code:, body:)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  def unit_norm(vector)
    Math.sqrt(vector.sum { |x| x**2 })
  end

  describe EmbeddingProviders::Gemini do
    subject(:provider) { described_class.new(api_key: "gk-test") }

    it "raises MissingApiKey when built without the Move's key" do
      expect { described_class.new.embed("x") }
        .to raise_error(EmbeddingProviders::Base::MissingApiKey)
    end

    it "returns a blank result for blank text without calling the API" do
      expect(provider.embed("  ").vector).to be_nil
    end

    it "returns a 1536-d, L2-normalized vector tagged with the gemini model" do
      stub_http(code: "200", body: { embedding: { values: Array.new(1536, 0.5) } }.to_json)

      result = provider.embed("hair dryer")

      expect(result.provider).to eq("gemini")
      expect(result.model).to eq("gemini-embedding-001")
      expect(result.vector.size).to eq(1536)
      expect(unit_norm(result.vector)).to be_within(0.0001).of(1.0)
    end

    it "raises on a non-2xx response, surfacing the status and vendor message" do
      stub_http(code: "403", body: { error: { message: "API key invalid" } }.to_json)

      expect { provider.embed("x") }.to raise_error(ProviderHttp::Error, /403.*API key invalid/)
    end

    it "raises when a 2xx response carries no values" do
      stub_http(code: "200", body: { embedding: {} }.to_json)

      expect { provider.embed("x") }.to raise_error(ProviderHttp::Error, /missing values/)
    end
  end

  describe EmbeddingProviders::Voyage do
    subject(:provider) { described_class.new(api_key: "vk-test") }

    it "raises MissingApiKey when built without the Move's key" do
      expect { described_class.new.embed("x") }
        .to raise_error(EmbeddingProviders::Base::MissingApiKey)
    end

    it "returns a blank result for blank text without calling the API" do
      expect(provider.embed("").vector).to be_nil
    end

    it "zero-pads its native 1024-d output to a 1536-d, L2-normalized vector" do
      native = Array.new(1024, 1.0)
      stub_http(code: "200", body: { data: [{ embedding: native }] }.to_json)

      result = provider.embed("hair dryer")

      expect(result.provider).to eq("voyage")
      expect(result.model).to eq("voyage-3-large")
      expect(result.vector.size).to eq(1536)
      # Padded tail is zero; head is non-zero — padding never bleeds into the body.
      expect(result.vector.last(1536 - 1024)).to all(eq(0.0))
      expect(result.vector.first(1024)).to all(be > 0.0)
      expect(unit_norm(result.vector)).to be_within(0.0001).of(1.0)
    end

    it "raises on a non-2xx response, surfacing the status and vendor message" do
      stub_http(code: "401", body: { error: { message: "Unauthorized" } }.to_json)

      expect { provider.embed("x") }.to raise_error(ProviderHttp::Error, /401.*Unauthorized/)
    end
  end

  describe "Base#fit_dimensions (zero-padding is cosine-preserving)" do
    # A bare adapter exposing the protected helper, to assert the padding math the
    # whole vendor-neutral design rests on.
    let(:adapter) do
      Class.new(EmbeddingProviders::Base) do
        def fit(vector) = fit_dimensions(vector)
      end.new
    end

    def cosine(vec_a, vec_b)
      dot = vec_a.zip(vec_b).sum { |x, y| x * y }
      dot / (Math.sqrt(vec_a.sum { |x| x**2 }) * Math.sqrt(vec_b.sum { |x| x**2 }))
    end

    it "pads a short vector to exactly 1536 with trailing zeros" do
      fitted = adapter.fit([3.0, 4.0])

      expect(fitted.size).to eq(1536)
      expect(fitted.drop(2)).to all(eq(0.0))
    end

    it "truncates a vector longer than 1536" do
      expect(adapter.fit(Array.new(2048, 1.0)).size).to eq(1536)
    end

    it "preserves cosine similarity of the native vectors after padding" do
      a = [1.0, 2.0, 3.0]
      b = [3.0, 2.0, 1.0]

      expect(cosine(adapter.fit(a), adapter.fit(b))).to be_within(0.0001).of(cosine(a, b))
    end
  end
end
