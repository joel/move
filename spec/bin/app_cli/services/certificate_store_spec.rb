require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/router-cmd/certificate_store"

RSpec.describe AppCLI::Services::CertificateStore do
  subject(:store) { described_class.new(dir: dir) }

  let(:dir) { Dir.mktmpdir }
  let(:leaf) { OpenSSL::X509::Certificate.new(File.read(store.cert_path)) }

  after { FileUtils.rm_rf(dir) }

  it "generates a CA name-constrained to the zone and a leaf it signs" do
    expect(store.ensure!).to eq(:generated_all)
    constraint = store.ca.extensions.find { |e| e.oid == "nameConstraints" }
    expect(constraint.critical?).to be(true)
    expect(constraint.value).to include("DNS:move-easy.docker", "DNS:.move-easy.docker")
    expect(leaf.verify(store.ca.public_key)).to be(true)
  end

  it "issues the leaf for the apex and one wildcard label" do
    store.ensure!
    san = leaf.extensions.find { |e| e.oid == "subjectAltName" }.value
    expect(san).to eq("DNS:*.move-easy.docker, DNS:move-easy.docker")
  end

  it "keeps the CA key out of the leaf directory the router mounts, and 0600" do
    store.ensure!
    expect(Dir.children(store.leaf_dir)).to contain_exactly("move-easy.docker.pem", "move-easy.docker-key.pem")
    expect(File.stat(store.ca_key_path).mode & 0o777).to eq(0o600)
  end

  it "is idempotent once everything is fresh" do
    store.ensure!
    expect(store.ensure!).to eq(:present)
  end

  it "renews only the leaf near expiry, keeping the trusted CA" do
    store.ensure!
    ca_pem = File.read(store.ca_cert_path)
    later = Class.new { def self.now = Time.now.utc + (820 * 86_400) }
    aged = described_class.new(dir: dir, clock: later)
    expect(aged.leaf_state).to eq(:expiring)
    expect(aged.ensure!).to eq(:renewed_leaf)
    expect(File.read(store.ca_cert_path)).to eq(ca_pem)
  end

  it "re-issues a leaf not signed by the current CA" do
    store.ensure!
    File.delete(store.ca_cert_path, store.ca_key_path)
    other = described_class.new(dir: Dir.mktmpdir)
    other.ensure!
    FileUtils.cp([other.ca_cert_path, other.ca_key_path], dir)
    expect(store.leaf_state).to eq(:foreign)
  end
end
