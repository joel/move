require "spec_helper"
require "thor"
require_relative "../../../../bin/cli-files/dns-cmd/dns_service"

RSpec.describe AppCLI::Services::DnsService do
  subject(:dns) { described_class.new(shell: Thor::Shell::Basic.new) }

  it "delegates the zone to the edge IP as a routing-only domain" do
    expect(dns.delegate_content).to eq("[Delegate]\nDNS=127.0.0.2\nDomains=~move-easy.docker\n")
  end

  # Without the `~`, resolved also adds the zone as a search suffix, so a failed
  # lookup like platform.isms.docker is retried as
  # platform.isms.docker.move-easy.docker and answered by move-dns.
  it "never makes the zone a search domain" do
    expect(dns.delegate_content).not_to match(/^Domains=[^~]/)
  end

  it "prints a bootstrap script that writes the same delegate" do
    expect(dns.bootstrap_script).to include(
      "printf '[Delegate]\\nDNS=127.0.0.2\\nDomains=~move-easy.docker\\n'",
      "/etc/systemd/dns-delegate.d/move-easy-docker.dns-delegate"
    )
  end
end
