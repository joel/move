#!/usr/bin/env ruby

module AppCLI
  module Services
    # Waits for a started app container to answer GET /up from inside the
    # container itself, so neither the published port nor a helper image is
    # involved. It gives up early when the container stops (a boot crash).
    class ReadinessCheck
      TIMEOUT_ENV = "MOVE_APP_READY_TIMEOUT".freeze
      DEFAULT_TIMEOUT = 60
      POLL_INTERVAL = 2
      PROBE = "curl --fail --silent --output /dev/null --max-time 5 http://localhost:9292/up".freeze

      # The timeout in seconds, from MOVE_APP_READY_TIMEOUT (default 60).
      # Raises on a value that is not a positive integer.
      def self.timeout(env = ENV)
        raw = env.fetch(TIMEOUT_ENV, "").strip
        return DEFAULT_TIMEOUT if raw.empty?
        return Integer(raw, 10) if raw.match?(/\A[1-9]\d*\z/)

        raise Thor::Error, "#{TIMEOUT_ENV} must be a whole number of seconds, got #{raw.inspect}."
      end

      def initialize(runner:, shell:, timeout:)
        @runner = runner
        @shell = shell
        @timeout = timeout
      end

      # @return [Boolean] true once /up answers 2xx; false when the container
      #   stops or the timeout passes first
      def ready?(container)
        shell.say("Waiting up to #{timeout}s for #{container} to answer /up")
        deadline = now + timeout
        loop do
          return false unless runner.container_running?(container)
          return true if runner.run("docker exec #{container} #{PROBE}", allow_failure: true, quiet: true)
          return false if now >= deadline

          sleep(POLL_INTERVAL)
        end
      end

      private

      attr_reader :runner, :shell, :timeout

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
