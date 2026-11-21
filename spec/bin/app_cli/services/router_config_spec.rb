require "spec_helper"
require "tmpdir"
require "yaml"
require_relative "../../../../bin/cli-files/router-cmd/router_config"

RSpec.describe AppCLI::Services::RouterConfig do
  subject(:config) { described_class.new }

  let(:routers) { config.routes_config.dig("http", "routers") }

  it "routes the app apex and the reserved hosts by exact Host rule" do
    expect(routers.transform_values { |r| r["rule"] }).to include(
      "app" => "Host(`move.move-easy.docker`)",
      "mail" => "Host(`mail.move-easy.docker`)",
      "storage" => "Host(`storage.move-easy.docker`)",
      "bucket" => "Host(`bucket.move-easy.docker`)"
    )
  end

  it "sends every single-label tenant host to the app at priority 1" do
    tenants = routers.fetch("tenants")
    expect(tenants).to include("service" => "app", "priority" => 1)
    expect(tenants["rule"]).to eq("HostRegexp(`^[a-z0-9-]+\\.move-easy\\.docker$`)")
  end

  it "keeps the exact Host routers at default (length) priority so they beat the catch-all" do
    expect(routers.except("tenants").values).to all(satisfy { |r| !r.key?("priority") })
  end

  it "prefixes bucket paths with the app bucket before the S3 gateway" do
    expect(routers.dig("bucket", "middlewares")).to eq(["bucket-prefix"])
    expect(config.middlewares.dig("bucket-prefix", "addPrefix", "prefix")).to eq("/move")
    expect(config.services.dig("bucket", "loadBalancer", "servers", 0, "url")).to eq("http://seaweedfs:8333")
  end

  it "uses only the file provider (no docker socket, no labels)" do
    expect(config.static_config["providers"].keys).to eq(["file"])
  end

  it "writes valid, alias-free YAML" do
    Dir.mktmpdir do |dir|
      described_class.new(dir: dir).write!
      routes = File.read(File.join(dir, "dynamic", "routes.yml"))
      expect(routes).not_to match(/[&*]id\d/)
      expect(YAML.safe_load(routes).dig("http", "routers", "tenants", "priority")).to eq(1)
      expect(YAML.safe_load_file(File.join(dir, "traefik.yml")).dig("entryPoints", "websecure", "address"))
        .to eq(":443")
    end
  end
end
