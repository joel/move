# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Gemini do
  subject(:provider) { described_class.new(api_key: "g-test") }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: "Garage", categories: ["Tools"], tags: [] } }
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

  def content_response(content)
    { candidates: [{ content: { parts: [{ text: content }] } }] }.to_json
  end

  it "raises a typed missing-key error (strict BYO) when built without a key" do
    expect { described_class.new.identify(image: image, context: context) }
      .to raise_error(RecognitionProviders::Base::MissingApiKey, /No API key set/)
  end

  describe "#summarize_contents" do
    let(:items) { [{ label: "Drill", category: "Tools" }] }

    it "sends a responseSchema description request (no image) and returns the string" do
      stub_http(code: "200", body: content_response({ description: "Tools" }.to_json))

      result = provider.summarize_contents(items: items)

      body = sent_body
      aggregate_failures do
        expect(result).to eq("Tools")
        expect(body.dig("generationConfig", "responseSchema", "required")).to eq(%w[description])
        parts = body.dig("contents", 0, "parts")
        expect(parts.map(&:keys).flatten).to eq(%w[text]) # text-only, no inlineData
        expect(parts.dig(0, "text")).to include("Drill", "Tools")
      end
    end
  end

  it "sends a responseSchema request with the model in the URL, key header, and inline image" do
    stub_http(code: "200", body: content_response({ objects: [] }.to_json))

    provider.identify(image: image, context: context)

    body = sent_body
    aggregate_failures do
      expect(sent_request.path).to include("models/gemini-2.5-flash:generateContent")
      expect(sent_request["x-goog-api-key"]).to eq("g-test")
      gen = body["generationConfig"]
      expect(gen["responseMimeType"]).to eq("application/json")
      items = gen.dig("responseSchema", "properties", "objects", "items")
      expect(items["required"]).to include("category", "tags")
      expect(items["required"]).not_to include("fragile", "count")
      expect(items["properties"]).not_to have_key("fragile")
      expect(items["properties"]).not_to have_key("count")
      # Gemini's schema dialect uses uppercase type enums.
      expect(items.dig("properties", "tags", "type")).to eq("ARRAY")
      # Canonical camelCase proto json_name for the inline image part.
      inline = body.dig("contents", 0, "parts", 1, "inlineData")
      expect(inline).to include("mimeType" => "image/jpeg", "data" => Base64.strict_encode64("bytes"))
    end
  end

  it "normalizes a responseSchema objects payload, including category" do
    content = { objects: [{ label: "drill", confidence: 0.95,
                            category: "Tools" }] }.to_json
    stub_http(code: "200", body: content_response(content))

    result = provider.identify(image: image, context: context)
    object = result.objects.first

    expect(result.provider).to eq("gemini")
    expect(object).to have_attributes(label: "drill", confidence: 0.95,
                                      category: "Tools")
  end

  it "treats an empty objects array as a legitimate zero-detection result" do
    stub_http(code: "200", body: content_response({ objects: [] }.to_json))

    expect(provider.identify(image: image, context: context).objects).to be_empty
  end

  it "raises (not a phantom empty box) when a 2xx body is prose with no JSON" do
    stub_http(code: "200", body: content_response("I cannot identify the contents."))

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /malformed JSON body/)
  end

  it "raises (not a phantom empty box) when a 2xx body has no objects array" do
    stub_http(code: "200", body: content_response({ result: "none" }.to_json))

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /no objects array/)
  end

  it "raises on a non-2xx response, surfacing the status and vendor message" do
    stub_http(code: "400", body: { error: { message: "API key not valid" } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /400.*API key not valid/)
  end

  it "surfaces an exhausted-quota error (429 RESOURCE_EXHAUSTED) without the key" do
    stub_http(code: "429", body: { error: {
      status: "RESOURCE_EXHAUSTED",
      message: "Quota exceeded for quota metric 'Generate requests'. Check your plan and billing details."
    } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error) { |e|
        expect(e.message).to match(/quota exceeded.*plan and billing/i)
        expect(e.message).not_to include("g-test")
      }
  end
end
