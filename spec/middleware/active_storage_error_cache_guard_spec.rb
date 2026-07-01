# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveStorageErrorCacheGuard do
  # Immutable headers AS attaches via `http_cache_forever` before it streams.
  let(:immutable) do
    { "cache-control" => "public, max-age=31536000, immutable", "etag" => "W/\"abc\"",
      "expires" => "Thu, 31 Dec 2037 23:55:55 GMT", "content-type" => "image/jpeg" }
  end

  # A downstream app that echoes a fixed status + headers.
  def response_for(path, status, headers)
    app = ->(_env) { [status, headers.dup, ["body"]] }
    described_class.new(app).call("PATH_INFO" => path)
  end

  def headers_for(...)
    response_for(...)[1]
  end

  context "when the response is an error (>= 400) under the Active Storage prefix" do
    subject(:headers) { headers_for("/rails/active_storage/representations/proxy/x/y/z.jpg", 404, immutable) }

    it "forces the response uncacheable" do
      expect(headers["cache-control"]).to eq("no-store")
    end

    it "strips the inherited freshness/validator headers" do
      expect(headers.keys).not_to include("etag", "expires")
    end

    it "leaves non-caching headers (content-type) intact" do
      expect(headers["content-type"]).to eq("image/jpeg")
    end

    it "applies to a 500 too" do
      expect(headers_for("/rails/active_storage/blobs/proxy/x/y.jpg", 500, immutable)["cache-control"])
        .to eq("no-store")
    end
  end

  context "when the response is successful (2xx) under the prefix" do
    subject(:headers) { headers_for("/rails/active_storage/representations/proxy/x/y/z.jpg", 200, immutable) }

    it "leaves the immutable cache header untouched (real variants stay cached)" do
      expect(headers["cache-control"]).to eq("public, max-age=31536000, immutable")
      expect(headers["etag"]).to eq("W/\"abc\"")
    end
  end

  it "leaves a 304 Not Modified under the prefix untouched" do
    headers = headers_for("/rails/active_storage/representations/proxy/x/y/z.jpg", 304, immutable)
    expect(headers["cache-control"]).to eq("public, max-age=31536000, immutable")
  end

  it "does not touch an error response outside the Active Storage prefix" do
    headers = headers_for("/moves/abc/boxes/def", 404, immutable)
    expect(headers["cache-control"]).to eq("public, max-age=31536000, immutable")
  end

  it "passes the status and body through unchanged" do
    status, _headers, body = response_for("/rails/active_storage/x", 404, immutable)
    expect(status).to eq(404)
    expect(body).to eq(["body"])
  end

  it "honours a custom routes prefix (tracks config.active_storage.routes_prefix)" do
    app = ->(_env) { [404, immutable.dup, ["body"]] }
    _s, headers, _b = described_class.new(app, "/media").call("PATH_INFO" => "/media/representations/x.jpg")
    expect(headers["cache-control"]).to eq("no-store")
  end

  it "falls back to the default prefix when given a blank one" do
    app = ->(_env) { [404, immutable.dup, ["body"]] }
    _s, headers, _b = described_class.new(app, nil).call("PATH_INFO" => "/rails/active_storage/x.jpg")
    expect(headers["cache-control"]).to eq("no-store")
  end

  # Guards the Rails middleware contract: options are passed POSITIONALLY via
  # `klass.new(app, *args)`. A keyword-only constructor would leave the prefix
  # unset here (nil) and raise on `start_with?` — this builds through the real
  # stack to catch that, which a direct `.new` never would.
  it "is constructed correctly through the real Rails middleware stack" do
    downstream = ->(_env) { [404, immutable.dup, ["body"]] }
    stack = ActionDispatch::MiddlewareStack.new
    stack.use described_class, "/media"
    built = stack.build(downstream)

    _s, headers, _b = built.call("PATH_INFO" => "/media/representations/x.jpg")
    expect(headers["cache-control"]).to eq("no-store")
  end
end
