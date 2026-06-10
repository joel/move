# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Anthropic do
  subject(:provider) { described_class.new }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: nil } }

  def stub_http(code:, body:)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")
  end

  it "raises when the API key is absent" do
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
    expect { provider.identify(image: image, context: context) }.to raise_error(/ANTHROPIC_API_KEY/)
  end

  it "normalizes detections from the messages content block" do
    content = "[{\"label\":\"chair\",\"confidence\":0.7,\"count\":1}]"
    stub_http(code: "200", body: { content: [{ text: content }] }.to_json)

    result = provider.identify(image: image, context: context)

    expect(result.provider).to eq("anthropic")
    expect(result.objects.map(&:label)).to eq(["chair"])
  end

  it "raises on a non-2xx response with the vendor message" do
    stub_http(code: "401", body: { error: { message: "invalid x-api-key" } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /401.*invalid x-api-key/)
  end

  it "raises (not a phantom empty box) when a 2xx message has no parseable JSON array" do
    stub_http(code: "200", body: { content: [{ text: "Sorry, I can't identify anything." }] }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /no parseable JSON array/)
  end
end
