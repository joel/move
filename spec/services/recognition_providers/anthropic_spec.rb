# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Anthropic do
  subject(:provider) { described_class.new }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: nil, categories: [], tags: [] } }

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

  it "normalizes detections from the forced tool_use input, including category + fragile" do
    body = { content: [{
      type: "tool_use", name: "record_objects",
      input: { objects: [{ label: "chair", confidence: 0.7, count: 1,
                           category: "Furniture", fragile: false }] }
    }] }.to_json
    stub_http(code: "200", body: body)

    result = provider.identify(image: image, context: context)
    object = result.objects.first

    expect(result.provider).to eq("anthropic")
    expect(object).to have_attributes(label: "chair", category: "Furniture", fragile: false)
  end

  it "treats an empty objects array as a legitimate zero-detection result" do
    body = { content: [{ type: "tool_use", name: "record_objects", input: { objects: [] } }] }.to_json
    stub_http(code: "200", body: body)

    expect(provider.identify(image: image, context: context).objects).to be_empty
  end

  it "raises on a non-2xx response with the vendor message" do
    stub_http(code: "401", body: { error: { message: "invalid x-api-key" } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /401.*invalid x-api-key/)
  end

  it "raises (not a phantom empty box) when the model answers in prose instead of the tool" do
    stub_http(code: "200", body: { content: [{ type: "text", text: "Sorry, I can't help." }] }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /no record_objects tool_use block/)
  end
end
