#!/usr/bin/env ruby

require "openssl"
require "fileutils"
require_relative "../edge/edge"

module AppCLI
  module Services
    # Per-developer TLS for *.move-easy.docker (port of ISMS CLI V2's
    # CertificateStore). `.docker` is not a public TLD, so each machine gets
    # its own root CA, name-constrained to the zone: trusting it can never vouch
    # for anything else. The CA is the trust anchor and only changes on
    # `rotate!`; the leaf renews itself (825 days is the browser cap).
    class CertificateStore
      DOMAIN = Edge::DOMAIN
      LEAF_NAMES = ["*.#{DOMAIN}", DOMAIN].freeze
      KEY_BITS = 2048
      CA_VALIDITY = 10 * 365 * 86_400
      LEAF_VALIDITY = 825 * 86_400
      RENEW_WINDOW = 30 * 86_400
      BACKDATE = 3600

      attr_reader :dir

      def initialize(dir: Edge::CERTS_DIR, clock: Time)
        @dir = dir
        @clock = clock
      end

      def ca_cert_path = File.join(dir, "rootCA.pem")
      def ca_key_path = File.join(dir, "rootCA-key.pem")
      def leaf_dir = File.join(dir, "leaf")
      def cert_path = File.join(leaf_dir, "#{DOMAIN}.pem")
      def key_path = File.join(leaf_dir, "#{DOMAIN}-key.pem")

      # Idempotent. Returns :generated_all, :renewed_leaf or :present.
      def ensure!
        if ca.nil?
          generate_ca
          generate_leaf
          :generated_all
        elsif leaf_state != :ok
          generate_leaf
          :renewed_leaf
        else
          :present
        end
      end

      def rotate!
        [ca_cert_path, ca_key_path, cert_path, key_path].each { |path| FileUtils.rm_f(path) }
        ensure!
      end

      # :missing, :expiring, :foreign (not signed by our CA), :names_changed or :ok.
      def leaf_state
        cert = read_cert(cert_path)
        authority = ca
        return :missing if cert.nil? || authority.nil?
        return :foreign unless cert.verify(authority.public_key)
        return :names_changed unless leaf_names(cert).sort == LEAF_NAMES.sort
        return :expiring if cert.not_after - @clock.now < RENEW_WINDOW

        :ok
      end

      def ca = read_cert(ca_cert_path)

      private

      def generate_ca
        key = OpenSSL::PKey::RSA.new(KEY_BITS)
        name = OpenSSL::X509::Name.new([["O", "Move local dev"], ["CN", "Move #{DOMAIN} dev CA"]])
        cert = blank_cert(subject: name, issuer: name, key: key, validity: CA_VALIDITY)
        ext = factory(cert, cert)
        cert.add_extension(ext.create_extension("basicConstraints", "CA:TRUE,pathlen:0", true))
        cert.add_extension(ext.create_extension("keyUsage", "keyCertSign,cRLSign", true))
        cert.add_extension(ext.create_extension("subjectKeyIdentifier", "hash"))
        # The teeth: a leaked dev CA can only ever vouch for this zone. Both
        # spellings — validators disagree on the dot-less form.
        cert.add_extension(ext.create_extension(
                             "nameConstraints", "permitted;DNS:#{DOMAIN},permitted;DNS:.#{DOMAIN}", true
                           ))
        cert.sign(key, OpenSSL::Digest.new("SHA256"))
        persist(ca_cert_path => cert.to_pem, ca_key_path => key.to_pem)
      end

      def generate_leaf
        authority = ca
        key = OpenSSL::PKey::RSA.new(KEY_BITS)
        cert = blank_cert(subject: OpenSSL::X509::Name.new([["CN", DOMAIN]]),
                          issuer: authority.subject, key: key, validity: LEAF_VALIDITY)
        ext = factory(cert, authority)
        cert.add_extension(ext.create_extension("basicConstraints", "CA:FALSE"))
        cert.add_extension(ext.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
        cert.add_extension(ext.create_extension("extendedKeyUsage", "serverAuth"))
        cert.add_extension(ext.create_extension("subjectAltName",
                                                LEAF_NAMES.map { |n| "DNS:#{n}" }.join(",")))
        cert.add_extension(ext.create_extension("authorityKeyIdentifier", "keyid"))
        cert.sign(OpenSSL::PKey::RSA.new(File.read(ca_key_path)), OpenSSL::Digest.new("SHA256"))
        persist(cert_path => cert.to_pem, key_path => key.to_pem)
      end

      def blank_cert(subject:, issuer:, key:, validity:)
        now = @clock.now
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = OpenSSL::BN.rand(128)
        cert.subject = subject
        cert.issuer = issuer
        cert.public_key = key.public_key
        cert.not_before = now - BACKDATE
        cert.not_after = now + validity
        cert
      end

      def factory(subject_cert, issuer_cert)
        OpenSSL::X509::ExtensionFactory.new.tap do |f|
          f.subject_certificate = subject_cert
          f.issuer_certificate = issuer_cert
        end
      end

      # Keys 0600 (the CA key is the dangerous one); certs world-readable so the
      # router container's user can read the bind-mounted leaf.
      def persist(files)
        files.each do |path, pem|
          FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
          tmp = "#{path}.tmp"
          File.write(tmp, pem)
          File.chmod(path.end_with?("-key.pem") ? 0o600 : 0o644, tmp)
          File.rename(tmp, path)
        end
        File.chmod(0o755, leaf_dir) if Dir.exist?(leaf_dir)
      end

      def leaf_names(cert)
        san = cert.extensions.find { |e| e.oid == "subjectAltName" }
        return [] unless san

        san.value.split(",").map { |entry| entry.strip.delete_prefix("DNS:") }
      end

      def read_cert(path)
        return nil unless File.file?(path)

        OpenSSL::X509::Certificate.new(File.read(path))
      rescue OpenSSL::X509::CertificateError
        nil
      end
    end
  end
end
