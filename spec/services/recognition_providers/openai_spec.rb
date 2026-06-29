# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Openai do
  subject(:provider) { described_class.new(api_key: "sk-test") }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: "Kitchen" } }
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

  it "raises a typed missing-key error (strict BYO) when built without a key" do
    expect { described_class.new.identify(image: image, context: context) }
      .to raise_error(RecognitionProviders::Base::MissingApiKey, /No API key set/)
  end

  describe "#summarize_contents" do
    let(:items) { [{ label: "Lamp", category: "Lighting" }] }

    it "sends a strict json_schema description request (no image) and returns the string" do
      stub_http(code: "200", body: content_response({ description: "Lighting" }.to_json))

      result = provider.summarize_contents(items: items)

      sent = sent_body
      aggregate_failures do
        expect(result).to eq("Lighting")
        expect(sent.dig("response_format", "json_schema", "name")).to eq("box_description")
        expect(sent.dig("response_format", "json_schema", "schema", "required")).to eq(%w[description])
        # Text-only content (a plain string, not the image multi-part array).
        expect(sent.dig("messages", 0, "content")).to be_a(String).and include("Lamp")
      end
    end

    it "raises on a missing description in a 2xx body" do
      stub_http(code: "200", body: content_response({ description: "" }.to_json))

      expect { provider.summarize_contents(items: items) }
        .to raise_error(ProviderHttp::Error, /no description/)
    end
  end

  it "sends a strict json_schema request with the auth header, model, and data-URL image" do
    stub_http(code: "200", body: content_response({ objects: [] }.to_json))

    provider.identify(image: image, context: context)

    body = sent_body
    aggregate_failures do
      expect(sent_request["authorization"]).to eq("Bearer sk-test")
      expect(body["model"]).to eq("gpt-5.5")
      expect(body["reasoning_effort"]).to eq("medium")
      fmt = body["response_format"]
      expect(fmt["type"]).to eq("json_schema")
      expect(fmt.dig("json_schema", "strict")).to be(true)
      items = fmt.dig("json_schema", "schema", "properties", "objects", "items")
      expect(items["required"]).to contain_exactly("label", "confidence")
      expect(items["properties"].keys).to contain_exactly("label", "confidence")
      content = body.dig("messages", 0, "content")
      expect(content.dig(0, "text")).to include("belongings").and include("floor")
      expect(content.dig(1, "image_url", "url"))
        .to eq("data:image/jpeg;base64,#{Base64.strict_encode64("bytes")}")
    end
  end

  it "normalizes a structured-output objects payload" do
    content = { objects: [{ label: "lamp", confidence: 0.9 }] }.to_json
    stub_http(code: "200", body: content_response(content))

    result = provider.identify(image: image, context: context)
    object = result.objects.first

    expect(result.provider).to eq("openai")
    expect(object).to have_attributes(label: "lamp", confidence: 0.9)
  end

  it "recovers a fenced JSON object via the backstop" do
    content = "```json\n#{{ objects: [{ label: "mug", confidence: 0.5,
                                        category: "Kitchenware" }] }.to_json}\n```"
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

  it "surfaces an exhausted-quota error (429 insufficient_quota) without the key" do
    stub_http(code: "429", body: { error: {
      message: "You exceeded your current quota, please check your plan and billing details.",
      type: "insufficient_quota"
    } }.to_json)

    expect { provider.identify(image: image, context: context) }
      .to raise_error(ProviderHttp::Error) { |e|
        expect(e.message).to match(/quota.*plan and billing/i)
        expect(e.message).not_to include("sk-test")
      }
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
