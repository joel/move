# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Openai do
  subject(:provider) { described_class.new }

  let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "bytes") }
  let(:context) { { room: "Kitchen" } }

  def stub_http(code:, body:)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test")
  end

  it "raises when the API key is absent" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
    expect { provider.identify(image: image, context: context) }.to raise_error(/OPENAI_API_KEY/)
  end

  it "normalizes a fenced JSON array of detections" do
    content = "```json\n[{\"label\":\"lamp\",\"confidence\":0.9,\"count\":2}]\n```"
    stub_http(code: "200", body: { choices: [{ message: { content: content } }] }.to_json)

    result = provider.identify(image: image, context: context)

    expect(result.provider).to eq("openai")
    expect(result.objects.map(&:label)).to eq(["lamp"])
    expect(result.objects.first.count).to eq(2)
    expect(result.objects.first.confidence).to eq(0.9)
  end

  it "yields no detections when the model returns unparseable content (not a transport error)" do
    stub_http(code: "200", body: { choices: [{ message: { content: "I see a lamp." } }] }.to_json)

    expect(provider.identify(image: image, context: context).objects).to be_empty
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
