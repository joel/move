# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Anthropic do
  subject(:provider) { described_class.new }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: nil, categories: [], tags: [] } }
  let(:captured) { {} }

  # Capture the outgoing request so request-body specs can assert what we SEND.
  def stub_http(code:, body:)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) { |req|
      captured[:request] = req
      response
    }
    allow(Net::HTTP).to receive(:start).and_yield(http).and_return(response)
  end

  def sent_request = captured.fetch(:request)
  def sent_body = JSON.parse(sent_request.body)

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")
  end

  it "raises when the API key is absent" do
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
    expect { provider.identify(image: image, context: context) }.to raise_error(/ANTHROPIC_API_KEY/)
  end

  it "sends a forced tool_use request with the auth/version headers, model, and base64 image" do
    body = { content: [{ type: "tool_use", name: "record_objects", input: { objects: [] } }] }.to_json
    stub_http(code: "200", body: body)

    provider.identify(image: image, context: context)

    sent = sent_body
    aggregate_failures do
      expect(sent_request["x-api-key"]).to eq("sk-ant-test")
      expect(sent_request["anthropic-version"]).to eq("2023-06-01")
      expect(sent["model"]).to eq("claude-haiku-4-5-20251001")
      expect(sent.dig("tool_choice", "type")).to eq("tool")
      expect(sent.dig("tool_choice", "name")).to eq("record_objects")
      tool = sent["tools"].first
      expect(tool["name"]).to eq("record_objects")
      expect(tool.dig("input_schema", "properties", "objects", "items", "required"))
        .to include("category", "fragile")
      expect(sent.dig("messages", 0, "content", 1, "source"))
        .to eq("type" => "base64", "media_type" => "image/jpeg", "data" => Base64.strict_encode64("bytes"))
    end
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
