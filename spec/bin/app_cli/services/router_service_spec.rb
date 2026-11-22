require "spec_helper"
require "thor"
require_relative "../../../../bin/cli-files/router-cmd/router_service"

RSpec.describe AppCLI::Services::RouterService do
  def upstream_for(env)
    service = described_class.new(shell: Thor::Shell::Basic.new, env: env)
    service.send(:config).services.dig("app", "loadBalancer", "servers", 0, "url")
  end

  around do |example|
    saved = ENV.delete("MOVE_APP_UPSTREAM")
    example.run
  ensure
    saved ? ENV["MOVE_APP_UPSTREAM"] = saved : ENV.delete("MOVE_APP_UPSTREAM")
  end

  it "routes the app container of the selected environment" do
    expect(upstream_for(nil)).to eq("http://move-app-dev:9292")
    expect(upstream_for("prod")).to eq("http://move-app-prod:9292")
  end

  it "honours the documented MOVE_APP_UPSTREAM override" do
    ENV["MOVE_APP_UPSTREAM"] = "http://host.docker.internal:3000"
    expect(upstream_for("prod")).to eq("http://host.docker.internal:3000")
  end

  describe ".same_cert?" do
    def self_signed
      key = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = rand(1..1_000_000)
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=t")
      cert.public_key = key.public_key
      cert.not_before = Time.now.utc
      cert.not_after = Time.now.utc + 60
      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      cert.to_pem
    end

    it "treats a rotated CA under the same nickname as untrusted" do
      current = self_signed
      expect(described_class.same_cert?(current, current)).to be(true)
      expect(described_class.same_cert?(self_signed, current)).to be(false)
      expect(described_class.same_cert?("", current)).to be(false)
    end
  end
end
