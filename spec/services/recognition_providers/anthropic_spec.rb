# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Anthropic do
  subject(:provider) { described_class.new(api_key: "sk-ant-test") }

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

  it "raises a typed missing-key error (strict BYO) when built without a key" do
    expect { described_class.new.identify(image: image, context: context) }
      .to raise_error(RecognitionProviders::Base::MissingApiKey, /No API key set/)
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
        .to include("category", "fragile", "tags")
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

  it "surfaces an exhausted-credit-balance error without the key" do
    stub_http(code: "400", body: { error: {
      message: "Your credit balance is too low to access the Anthropic API."
    } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error) { |e|
        expect(e.message).to match(/credit balance is too low/i)
        expect(e.message).not_to include("sk-ant-test")
      }
  end

  it "raises (not a phantom empty box) when the model answers in prose instead of the tool" do
    stub_http(code: "200", body: { content: [{ type: "text", text: "Sorry, I can't help." }] }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /no record_objects tool_use block/)
  end

  describe "#summarize_contents" do
    let(:items) { [{ label: "Mugs", category: "Kitchenware", count: 4 }, { label: "Books", category: "Books", count: 1 }] }

    it "sends a forced description-tool request (no image) and returns the description" do
      body = { content: [{ type: "tool_use", name: "record_description",
                           input: { description: "Kitchenware, Books" } }] }.to_json
      stub_http(code: "200", body: body)

      result = provider.summarize_contents(items: items)

      sent = sent_body
      aggregate_failures do
        expect(result).to eq("Kitchenware, Books")
        expect(sent.dig("tool_choice", "name")).to eq("record_description")
        expect(sent.dig("tools", 0, "input_schema", "required")).to eq(%w[description])
        # Text-only: a single text block, no image source.
        expect(sent.dig("messages", 0, "content").pluck("type")).to eq(%w[text])
        expect(sent.dig("messages", 0, "content", 0, "text")).to include("Mugs", "Kitchenware")
      end
    end

    it "raises a typed missing-key error (strict BYO) when built without a key" do
      expect { described_class.new.summarize_contents(items: items) }
        .to raise_error(RecognitionProviders::Base::MissingApiKey)
    end

    it "raises when the model answers in prose instead of the tool" do
      stub_http(code: "200", body: { content: [{ type: "text", text: "Box of stuff" }] }.to_json)

      expect { provider.summarize_contents(items: items) }
        .to raise_error(ProviderHttp::Error, /no record_description tool_use block/)
    end
  end
end
