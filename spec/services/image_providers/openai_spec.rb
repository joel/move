# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageProviders::Openai do
  subject(:provider) { described_class.new(api_key: "sk-test") }

  let(:captured) { {} }

  def stub_http(code:, body:)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) { |req|
      captured[:request] = req
      response
    }
    allow(Net::HTTP).to receive(:start).and_yield(http).and_return(response)
  end

  it "raises a typed missing-key error (strict BYO) when built without a key" do
    expect { described_class.new.generate(prompt: "x") }
      .to raise_error(ImageProviders::Base::MissingApiKey, /No API key set/)
  end

  it "sends the auth header, model, prompt and size, and decodes the b64 image" do
    png = ImageProviders::Fake.new.generate(prompt: "x").image_bytes
    stub_http(code: "200", body: { data: [{ b64_json: Base64.strict_encode64(png) }] }.to_json)

    result = provider.generate(prompt: "a brass lamp")

    body = JSON.parse(captured.fetch(:request).body)
    aggregate_failures do
      expect(captured.fetch(:request)["authorization"]).to eq("Bearer sk-test")
      expect(body["model"]).to eq(described_class::DEFAULT_MODEL)
      expect(body["prompt"]).to eq("a brass lamp")
      expect(body["size"]).to eq(described_class::SIZE)
      expect(result.image_bytes).to eq(png)
      expect(result.content_type).to eq("image/png")
    end
  end

  it "raises when a 2xx body carries no image data" do
    stub_http(code: "200", body: { data: [{}] }.to_json)

    expect { provider.generate(prompt: "x") }
      .to raise_error(ProviderHttp::Error, /no image data/)
  end

  it "raises on a non-2xx response, surfacing the status without the key" do
    stub_http(code: "429", body: { error: { message: "Rate limit reached" } }.to_json)

    expect { provider.generate(prompt: "x") }
      .to raise_error(ProviderHttp::Error) { |e|
        expect(e.message).to match(/429.*Rate limit reached/)
        expect(e.message).not_to include("sk-test")
      }
  end
end
