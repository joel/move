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
end
