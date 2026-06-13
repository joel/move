# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Openai do
  subject(:provider) { described_class.new }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: "Kitchen", categories: ["Lighting"], tags: [] } }
  let(:captured) { {} }

  # Capture the outgoing request so request-body specs can assert what we SEND
  # (the adapters have no real-API CI coverage). start yields a stub http whose
  # #request records the Net::HTTP::Post; the block runs, then start returns the
  # canned response — so the response-parsing specs are unaffected.
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
    { choices: [{ message: { content: content } }] }.to_json
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
  end

  it "raises when the API key is absent" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
    expect { provider.identify(image: image, context: context) }.to raise_error(/OPENAI_API_KEY/)
  end

  it "sends a strict json_schema request with the auth header, model, and data-URL image" do
    stub_http(code: "200", body: content_response({ objects: [] }.to_json))

    provider.identify(image: image, context: context)

    body = sent_body
    aggregate_failures do
      expect(sent_request["authorization"]).to eq("Bearer sk-test")
      expect(sent_request["content-type"]).to eq("application/json")
      expect(body["model"]).to eq("gpt-5-mini")
      fmt = body["response_format"]
      expect(fmt["type"]).to eq("json_schema")
      expect(fmt.dig("json_schema", "strict")).to be(true)
      items = fmt.dig("json_schema", "schema", "properties", "objects", "items")
      expect(items["required"]).to include("category", "fragile")
      expect(items.dig("properties", "fragile", "type")).to eq("boolean")
      content = body.dig("messages", 0, "content")
      expect(content.dig(0, "text")).to include("moving-box photo")
      expect(content.dig(1, "image_url", "url"))
        .to eq("data:image/jpeg;base64,#{Base64.strict_encode64("bytes")}")
    end
  end

  it "normalizes a structured-output objects payload, including category + fragile" do
    content = { objects: [{ label: "lamp", confidence: 0.9, count: 2,
                            category: "Lighting", fragile: true }] }.to_json
    stub_http(code: "200", body: content_response(content))

    result = provider.identify(image: image, context: context)
    object = result.objects.first

    expect(result.provider).to eq("openai")
    expect(object).to have_attributes(label: "lamp", count: 2, confidence: 0.9,
                                      category: "Lighting", fragile: true)
  end

  it "recovers a fenced JSON object via the backstop" do
    content = "```json\n#{{ objects: [{ label: "mug", confidence: 0.5, count: 1,
                                        category: "Kitchenware", fragile: false }] }.to_json}\n```"
    stub_http(code: "200", body: content_response(content))

    expect(provider.identify(image: image, context: context).objects.map(&:label)).to eq(["mug"])
  end

  it "treats an empty objects array as a legitimate zero-detection result" do
    stub_http(code: "200", body: content_response({ objects: [] }.to_json))

    expect(provider.identify(image: image, context: context).objects).to be_empty
  end

  it "raises (not a phantom empty box) when a 2xx body has no objects array" do
    stub_http(code: "200", body: content_response({ note: "no objects here" }.to_json))

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /no objects array/)
  end

  it "raises (not a phantom empty box) when a 2xx message is prose with no JSON" do
    stub_http(code: "200", body: content_response("I see a lamp and a chair."))

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /malformed JSON body/)
  end

  it "raises when a 2xx message is malformed JSON" do
    stub_http(code: "200", body: content_response("{bad json"))

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /malformed JSON body/)
  end

  it "raises on a non-2xx response, surfacing the status and vendor message (never the key)" do
    stub_http(code: "429", body: { error: { message: "Rate limit reached" } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /429.*Rate limit reached/)
  end

  it "raises a clean status error even when the error body is not JSON" do
    stub_http(code: "502", body: "<html>Bad Gateway</html>")

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /HTTP 502/)
  end

  it "raises (not a phantom empty success) when a 2xx body is not JSON" do
    stub_http(code: "200", body: "<html>Proxy interstitial</html>")

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error, /2xx with a non-JSON body/)
  end
end
