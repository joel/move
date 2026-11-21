#!/usr/bin/env ruby

require "open3"
require "openssl"
require "socket"
require_relative "../edge/edge"
require_relative "certificate_store"
require_relative "router_config"

module AppCLI
  module Services
    # move-router: Traefik terminating TLS for *.move-easy.docker on the edge
    # IP and routing by Host header (ISMS CLI V2 router pattern). Per-machine
    # state (rendered config, leaf cert) is bind-mounted read-only; `start`
    # re-renders it every time, and `watch: true` applies route edits live.
    class RouterService
      CONTAINER = "#{APP_NAME}-router".freeze
      IMAGE = "traefik:#{ENV.fetch("MOVE_TRAEFIK_VERSION", "v3.7.8")}".freeze
      PROBE_HOST = "#{APP_NAME}.#{Edge::DOMAIN}".freeze
      NSS_DB = "sql:#{File.join(Dir.home, ".pki/nssdb")}".freeze
      NSS_NICKNAME = "Move #{Edge::DOMAIN} dev CA".freeze
      NSS_DIR = File.join(Dir.home, ".pki/nssdb").freeze
      QUIET = { out: File::NULL, err: File::NULL }.freeze

      # env picks the app upstream (move-app-dev or move-app-prod) and the extra
      # network the router must join to reach it; mail/storage stay on the dev one.
      def initialize(shell:, env: nil, certs: CertificateStore.new, config: nil)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
        @env_config = EnvConfig.new(env)
        @certs = certs
        @config = config || RouterConfig.new(app_upstream: app_upstream)
      end

      # Certs + routes. Only env-aware entry points (start/install [ENV]) call
      # this: re-rendering routes for the default env would repoint a running
      # prod router at the dev app.
      def install
        ensure_certs
        config.write!
      end

      def ensure_certs
        result = certs.ensure!
        shell.say("New root CA at #{certs.ca_cert_path} - run `bin/cli router trust`.") if result == :generated_all
        result
      end

      def build
        install
        runner.ensure_network(NETWORK_NAME)
        runner.run("docker pull #{IMAGE}") unless runner.image_exists?(IMAGE)
      end

      def start
        build
        if runner.container_running?(CONTAINER)
          join_app_network
          return shell.say("Router already running (routes re-rendered for #{env_config.app_container}).")
        end

        runner.run("docker rm -f #{CONTAINER}", allow_failure: true, quiet: true)
        runner.run(run_command)
        join_app_network
        wait_for_ping
        shell.say("Router up: https://#{PROBE_HOST}")
        warn_untrusted
      end

      def stop
        return shell.say("Router not running, skipping stop.") unless runner.container_running?(CONTAINER)

        runner.run("docker stop #{CONTAINER}")
      end

      def status = runner.container_status(CONTAINER)

      def logs(follow: true)
        runner.run(["docker logs", ("-f" if follow), CONTAINER].compact)
      end

      def rotate_certs
        certs.rotate!
        shell.say("New root CA generated. Run `bin/cli router trust` and `bin/cli router restart`.")
      end

      # Per-user trust in the NSS store Chrome/Chromium/Brave read. No sudo.
      def trust
        raise Thor::Error, "certutil missing: sudo apt install libnss3-tools" unless system("which", "certutil", **QUIET)

        # Certs only: re-rendering routes here would point a running prod router
        # back at the dev app.
        ensure_certs
        ensure_nss_db
        runner.run(["certutil -d #{NSS_DB} -D -n #{Shellwords.escape(NSS_NICKNAME)} 2>/dev/null"],
                   allow_failure: true, quiet: true)
        runner.run(["certutil -d #{NSS_DB} -A -t C,, -n #{Shellwords.escape(NSS_NICKNAME)}",
                    "-i #{Shellwords.escape(certs.ca_cert_path)}"])
        shell.say("Trusted #{certs.ca_cert_path} for this user. Restart the browser.")
      end

      # The nickname alone is not enough: after a CA rotation the NSS store can
      # still hold the OLD cert under it. Compare the exported cert to ours.
      def trusted?
        pem, status = Open3.capture2("certutil", "-d", NSS_DB, "-L", "-n", NSS_NICKNAME, "-a",
                                     err: File::NULL)
        status.success? && self.class.same_cert?(pem, File.read(certs.ca_cert_path))
      rescue Errno::ENOENT
        false
      end

      def self.same_cert?(pem_a, pem_b)
        OpenSSL::X509::Certificate.new(pem_a).to_der == OpenSSL::X509::Certificate.new(pem_b).to_der
      rescue OpenSSL::X509::CertificateError
        false
      end

      # Full-edge verification, independent of DNS: container, certs, a real TLS
      # handshake on the edge IP verified against OUR CA, then user trust.
      def check
        failures = []
        failures << "router not running (bin/cli router start)" unless runner.container_running?(CONTAINER)
        state = certs.leaf_state
        failures << "TLS material is #{state} (bin/cli router restart)" unless state == :ok
        failures << handshake_error if failures.empty? && handshake_error
        failures << "CA not trusted for this user (bin/cli router trust)" unless trusted?
        report(failures)
      end

      private

      attr_reader :runner, :shell, :certs, :config, :env_config

      # MOVE_APP_UPSTREAM (documented) wins over the env-derived container.
      def app_upstream
        ENV.fetch("MOVE_APP_UPSTREAM") { "http://#{env_config.app_container}:9292" }
      end

      # A pristine profile has no NSS database; certutil -A cannot create one.
      def ensure_nss_db
        FileUtils.mkdir_p(NSS_DIR)
        return if File.exist?(File.join(NSS_DIR, "cert9.db"))

        runner.run("certutil -d #{NSS_DB} -N --empty-password")
      end

      # The prod app lives on the suffixed network; mail/storage on the dev one.
      def join_app_network
        network = env_config.network_name
        return if network == NETWORK_NAME

        runner.ensure_network(network)
        system("docker", "network", "connect", network, CONTAINER, **QUIET)
      end

      def run_command
        [
          "docker run --rm --detach",
          "--name #{CONTAINER}",
          "--network #{NETWORK_NAME}",
          "--publish #{Edge::IP}:443:443",
          "--publish #{Edge::IP}:80:80",
          "--volume #{Edge::ROUTER_DIR}:/etc/traefik:ro",
          "--volume #{certs.leaf_dir}:/certs:ro",
          IMAGE
        ]
      end

      def wait_for_ping(attempts: 20)
        attempts.times do
          return if system("docker", "exec", CONTAINER, "traefik", "healthcheck", "--ping", **QUIET)

          sleep(0.5)
        end
        raise Thor::Error, "Router did not answer its ping. See `bin/cli router logs`."
      end

      def warn_untrusted
        return if trusted?

        shell.say("Root CA not trusted yet - run `bin/cli router trust`, then restart the browser.", :yellow)
      end

      def handshake_error
        return @handshake_error if defined?(@handshake_error)

        @handshake_error = attempt_handshake
      end

      def attempt_handshake
        store = OpenSSL::X509::Store.new
        store.add_file(certs.ca_cert_path)
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, cert_store: store)
        socket = Socket.tcp(Edge::IP, 443, connect_timeout: 3)
        ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
        ssl.hostname = PROBE_HOST
        ssl.sync_close = true
        ssl.connect
        ssl.post_connection_check(PROBE_HOST)
        ssl.close
        nil
      rescue OpenSSL::SSL::SSLError, SystemCallError, SocketError, IOError => e
        "TLS handshake on #{Edge::IP}:443 failed (#{e.class}: #{e.message})"
      end

      def report(failures)
        return shell.say("Router OK: https://#{PROBE_HOST} verifies against the dev CA.") if failures.empty?

        failures.each { |f| shell.say("✗ #{f}", :red) }
        raise Thor::Error, "Router check failed."
      end
    end
  end
end
