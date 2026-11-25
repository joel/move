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

  describe "a worktree zone leaf" do
    let(:zone) { "w1.wt.move-easy.docker" }
    let(:zone_leaf) { OpenSSL::X509::Certificate.new(File.read(store.zone_cert_path(zone))) }

    it "covers one label under the zone, signed by the same CA" do
      store.ensure!
      expect(store.ensure_zone_leaf!(zone)).to eq(:generated)
      san = zone_leaf.extensions.find { |e| e.oid == "subjectAltName" }.value
      expect(san).to eq("DNS:*.w1.wt.move-easy.docker")
      expect(zone_leaf.verify(store.ca.public_key)).to be(true)
      expect(store.leaf_state).to eq(:ok)
    end

    it "is idempotent and renews near expiry" do
      store.ensure!
      store.ensure_zone_leaf!(zone)
      expect(store.ensure_zone_leaf!(zone)).to eq(:present)
      later = Class.new { def self.now = Time.now.utc + (820 * 86_400) }
      expect(described_class.new(dir: dir, clock: later).ensure_zone_leaf!(zone)).to eq(:generated)
    end

    it "verifies under the CA's name constraint, as a browser would" do
      store.ensure!
      store.ensure_zone_leaf!(zone)
      x509 = OpenSSL::X509::Store.new.tap { |s| s.add_cert(store.ca) }
      expect(x509.verify(zone_leaf)).to be(true)
    end

    it "refuses a name outside the CA's zone, or without a CA" do
      expect { store.ensure_zone_leaf!(zone) }.to raise_error(ArgumentError)
      store.ensure!
      expect { store.ensure_zone_leaf!("evil.example") }.to raise_error(ArgumentError)
    end

    it "is re-issued under the new CA on rotate!" do
      store.ensure!
      store.ensure_zone_leaf!(zone)
      store.rotate!
      expect(store.served_zones).to eq([zone])
      expect(zone_leaf.verify(store.ca.public_key)).to be(true)
    end

    it "is removed without touching the main leaf" do
      store.ensure!
      store.ensure_zone_leaf!(zone)
      store.remove_zone_leaf(zone)
      expect(Dir.children(store.leaf_dir)).to contain_exactly("move-easy.docker.pem", "move-easy.docker-key.pem")
    end
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

  it "regenerates the CA when its private key is missing" do
    store.ensure!
    File.delete(store.ca_key_path)
    expect(store.ensure!).to eq(:generated_all)
    expect(leaf.verify(store.ca.public_key)).to be(true)
  end

  it "regenerates the CA when its private key does not match" do
    store.ensure!
    File.write(store.ca_key_path, OpenSSL::PKey::RSA.new(2048).to_pem)
    expect(store.ensure!).to eq(:generated_all)
    expect(store.ca_usable?).to be(true)
  end

  it "re-issues the leaf when its private key is missing or replaced" do
    store.ensure!
    File.delete(store.key_path)
    expect(store.leaf_state).to eq(:key_mismatch)
    expect(store.ensure!).to eq(:renewed_leaf)
    File.write(store.key_path, OpenSSL::PKey::RSA.new(2048).to_pem)
    expect(store.ensure!).to eq(:renewed_leaf)
    expect(store.leaf_state).to eq(:ok)
  end
end
