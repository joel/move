#!/usr/bin/env ruby

require_relative "../edge/edge"

module AppCLI
  module Services
    # move-dns: dnsmasq answering *.move-easy.docker with the edge IP (ISMS CLI
    # V2 dns pattern). Host routing is a systemd-resolved DNS delegate scoped to
    # the zone — root's to write, so the CLI only prints it (`bootstrap`). A
    # delegate (systemd 258+), not a resolved.conf.d drop-in: drop-ins merge into
    # ONE global server list, which would mix this server with the ISMS one.
    class DnsService
      CONTAINER = "#{APP_NAME}-dns".freeze
      IMAGE = "#{APP_NAME}/dns:latest".freeze
      BUILD_DIR = File.join(AppCLI::ROOT, "config/dns").freeze
      PROBE_HOST = "#{APP_NAME}.#{Edge::DOMAIN}".freeze

      def initialize(shell:)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
      end

      def build(force: false)
        runner.ensure_network(NETWORK_NAME)
        return if runner.image_exists?(IMAGE) && !force

        runner.run("docker build --tag #{IMAGE} #{BUILD_DIR}")
      end

      def start
        build
        return shell.say("DNS already running.") if runner.container_running?(CONTAINER)

        runner.run("docker rm -f #{CONTAINER}", allow_failure: true, quiet: true)
        runner.run(run_command)
        wait_until_answering
        shell.say("Run `bin/cli dns bootstrap` once if the host resolver is not set up.") unless delegate_configured?
      end

      def stop
        return shell.say("DNS not running, skipping stop.") unless runner.container_running?(CONTAINER)

        runner.run("docker stop #{CONTAINER}")
      end

      def status = runner.container_status(CONTAINER)

      def logs(follow: true)
        runner.run(["docker logs", ("-f" if follow), CONTAINER].compact)
      end

      def delegate_content
        "[Delegate]\nDNS=#{Edge::IP}\nDomains=~#{Edge::DOMAIN}\n"
      end

      # The one root-only step, printed for the developer to run.
      MIN_SYSTEMD = 258 # first release with /etc/systemd/dns-delegate.d

      def bootstrap_script(systemd: systemd_version)
        unless delegates_supported?(systemd)
          raise Thor::Error, "systemd #{systemd || "(unknown)"} has no DNS delegates (needs #{MIN_SYSTEMD}+). " \
                             "A resolved.conf.d drop-in is NOT a substitute: it merges into the one " \
                             "global server list. Upgrade systemd, or point a single name at " \
                             "#{Edge::IP} in /etc/hosts per host you need."
        end

        <<~SH
          # Route *.#{Edge::DOMAIN} to move-dns (systemd-resolved DNS delegate).
          sudo mkdir -p #{File.dirname(Edge::DELEGATE_PATH)}
          printf '#{delegate_content.gsub("\n", "\\n")}' | sudo tee #{Edge::DELEGATE_PATH} >/dev/null
          sudo systemctl restart systemd-resolved
          resolvectl flush-caches
        SH
      end

      def delegate_configured?
        File.file?(Edge::DELEGATE_PATH) && File.read(Edge::DELEGATE_PATH).split == delegate_content.split
      end

      # getent goes through NSS (the path browsers use); dig/nslookup bypass it.
      def resolves?(name = PROBE_HOST)
        out = runner.capture("getent ahostsv4 #{name}", quiet: true).to_s
        out.lines.any? { |line| line.split.first == Edge::IP }
      end

      def check
        failures = []
        failures << "move-dns not running (bin/cli dns start)" unless runner.container_running?(CONTAINER)
        failures << "DNS delegate missing or stale (bin/cli dns bootstrap)" unless delegate_configured?
        failures << unsupported_systemd_message unless delegates_supported?
        failures << "#{PROBE_HOST} does not resolve to #{Edge::IP} via the system resolver" unless resolves?
        return shell.say("DNS OK: #{PROBE_HOST} -> #{Edge::IP}") if failures.empty?

        failures.each { |f| shell.say("✗ #{f}", :red) }
        raise Thor::Error, "DNS check failed."
      end

      private

      attr_reader :runner, :shell

      def delegates_supported?(version = systemd_version)
        !version.nil? && version >= MIN_SYSTEMD
      end

      def unsupported_systemd_message
        "systemd #{systemd_version || "(unknown)"} ignores dns-delegate.d (needs #{MIN_SYSTEMD}+)"
      end

      def systemd_version
        out = runner.capture("systemctl --version", quiet: true).to_s
        out[/\Asystemd (\d+)/, 1]&.to_i
      end

      def run_command
        [
          "docker run --rm --detach",
          "--name #{CONTAINER}",
          "--network #{NETWORK_NAME}",
          "--publish #{Edge::IP}:53:53/tcp",
          "--publish #{Edge::IP}:53:53/udp",
          IMAGE
        ]
      end

      def wait_until_answering(attempts: 20)
        attempts.times do
          return if system("docker", "exec", CONTAINER, "nslookup", PROBE_HOST, "127.0.0.1",
                           out: File::NULL, err: File::NULL)

          sleep(0.5)
        end
        raise Thor::Error, "move-dns did not answer #{PROBE_HOST}. See `bin/cli dns logs`."
      end
    end
  end
end
