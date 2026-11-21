#!/usr/bin/env ruby

require "json"
require_relative "../services/helpers"

module AppCLI
  module Services
    # Local SeaweedFS object store (S3-compatible) backing Active
    # Storage in dev. Mirrors MailService: a detached container on the
    # shared Traefik network. The Web UI is exposed at the storage host,
    # while the bucket host keeps browser/S3 access bucket-scoped.
    # Persistence via a named volume so blobs survive restarts.
    class StorageService
      STORAGE_CONTAINER = "seaweedfs".freeze
      STORAGE_IMAGE = "chrislusf/seaweedfs:3.97".freeze
      S3_PORT = "8333".freeze
      WEB_UI_PORT = "8888".freeze
      DEV_MIN_FREE_SPACE = "100MiB".freeze
      DEV_VOLUME_SIZE_LIMIT_MB = "64".freeze
      STORAGE_VOLUME = "#{Services::APP_NAME}-seaweedfs-data".freeze
      STORAGE_BUCKET = Services::APP_NAME
      SERVER_ARGS = [
        "server",
        "-s3",
        "-dir=/data",
        "-ip.bind=0.0.0.0",
        "-volume.minFreeSpace=#{DEV_MIN_FREE_SPACE}",
        "-master.volumePreallocate=false",
        "-master.volumeSizeLimitMB=#{DEV_VOLUME_SIZE_LIMIT_MB}"
      ].freeze
      # storage./bucket.move-easy.docker are routed by move-router (router_config.rb).
      # App origin allowed to direct-upload (dev).
      APP_ORIGIN_HOST = "#{Services::APP_NAME}.#{Services::DEV_DOMAIN}".freeze

      def initialize(shell:)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
      end

      def setup
        runner.ensure_network(Services::NETWORK_NAME)
        runner.ensure_volume(STORAGE_VOLUME)
      end

      def build
        if runner.image_exists?(STORAGE_IMAGE)
          shell.say("Storage image #{STORAGE_IMAGE} already present, skipping pull.")
        else
          shell.say("Pulling #{STORAGE_IMAGE} image")
          runner.run("docker pull #{STORAGE_IMAGE}")
        end
      end

      def start
        runner.ensure_network(Services::NETWORK_NAME)
        runner.ensure_volume(STORAGE_VOLUME)

        status = runner.container_status(STORAGE_CONTAINER)
        if status == "running" && !runtime_config_current?
          shell.say("Storage service is running with stale routing; recreating it.")
          stop
          status = runner.container_status(STORAGE_CONTAINER)
        end

        if status == "running"
          shell.say("Storage service already running.")
          return await_ready_and_provision
        end

        if status != "missing"
          shell.say("Removing existing storage container (status: #{status}).")
          runner.run("docker rm #{STORAGE_CONTAINER}", allow_failure: true)
        end

        runner.run(storage_run_command)
        await_ready_and_provision
      end

      # Block until S3 + the web UI answer, then provision the bucket and CORS.
      def await_ready_and_provision
        wait_for_s3_ready
        wait_for_web_ui_ready
        ensure_bucket
        ensure_cors
      end

      def stop
        if runner.container_running?(STORAGE_CONTAINER)
          shell.say("Stopping storage service container")
          runner.run("docker stop #{STORAGE_CONTAINER}")
        else
          shell.say("Storage service not running, skipping stop.")
        end
      end

      def teardown
        stop
        if runner.volume_exists?(STORAGE_VOLUME)
          runner.remove_volume(STORAGE_VOLUME)
        else
          shell.say("Docker volume '#{STORAGE_VOLUME}' not found, skipping removal.")
        end
      end

      def logs(follow: true)
        args = follow ? "-f" : ""
        runner.run("docker logs #{args} #{STORAGE_CONTAINER}")
      end

      def status
        runner.container_status(STORAGE_CONTAINER)
      end

      # SeaweedFS does not auto-create S3 buckets. CreateBucket is a
      # plain `PUT /<bucket>` on the S3 endpoint (anonymous is allowed
      # — no -s3.config), idempotent (2xx whether or not it already
      # exists). Provisioning failures are fatal — a "started" service
      # with no bucket/CORS silently breaks every direct upload.
      def ensure_bucket
        code = curl_status(
          "-X PUT http://localhost:#{S3_PORT}/#{STORAGE_BUCKET}"
        )
        # 409 = BucketAlreadyOwnedByYou — already provisioned, which
        # is success for an idempotent ensure.
        return if success_code?(code) || code == "409"

        raise Thor::Error,
              "SeaweedFS bucket provisioning failed " \
              "(HTTP #{code || "no response"}). Direct uploads " \
              "would be broken; not reporting success."
      end

      # Active Storage Direct Upload PUTs from the app origin to the
      # storage origin (cross-origin) — the browser preflights it, so
      # the bucket needs a CORS policy or every direct upload is
      # blocked. Idempotent (PutBucketCors overwrites).
      def ensure_cors
        require "tempfile"
        Tempfile.create(["cors", ".xml"]) do |f|
          f.write(cors_config)
          f.flush
          code = curl_status(
            "-X PUT --data-binary @#{f.path} " \
            "'http://localhost:#{S3_PORT}/" \
            "#{STORAGE_BUCKET}?cors'"
          )
          next if success_code?(code)

          raise Thor::Error,
                "SeaweedFS CORS provisioning failed " \
                "(HTTP #{code || "no response"}). Direct uploads " \
                "would be blocked; not reporting success."
        end
      end

      private

      def runtime_config_current?
        container_args == SERVER_ARGS
      end

      def container_args
        output = runner.capture(
          "docker inspect #{STORAGE_CONTAINER} --format '{{ json .Args }}'",
          quiet: true
        )
        JSON.parse(output.to_s)
      rescue JSON::ParserError
        []
      end

      # Poll the S3 endpoint until it answers (the container is up but
      # the S3 gateway needs a moment). Fail fast if it never does, so
      # `storage start` does not falsely report success.
      def wait_for_s3_ready(attempts: 30, interval: 1)
        i = 0
        while i < attempts
          ready = success_code?(
            curl_status("http://localhost:#{S3_PORT}/")
          )
          break if ready

          shell.say("Waiting for SeaweedFS S3…") if (i % 5).zero?
          sleep(interval)
          i += 1
        end
        return if i < attempts

        raise Thor::Error,
              "SeaweedFS S3 endpoint did not become ready on " \
              "localhost:#{S3_PORT} after #{attempts}s."
      end

      def wait_for_web_ui_ready(attempts: 30, interval: 1)
        i = 0
        while i < attempts
          ready = success_code?(
            curl_status("http://localhost:#{WEB_UI_PORT}/")
          )
          break if ready

          shell.say("Waiting for SeaweedFS Web UI...") if (i % 5).zero?
          sleep(interval)
          i += 1
        end
        return if i < attempts

        raise Thor::Error,
              "SeaweedFS Web UI did not become ready on " \
              "localhost:#{WEB_UI_PORT} after #{attempts}s."
      end

      # Returns the HTTP status string (e.g. "200") or nil if curl
      # could not connect. The "%{http_code}" is curl's own format
      # syntax, not a Ruby format string.
      # rubocop:disable-next Style/FormatStringToken
      def curl_status(args)
        runner.capture(
          %(curl -s -o /dev/null -w "%{http_code}" #{args}),
          quiet: true
        )&.strip
      end

      def success_code?(code)
        code.to_s.match?(/\A2\d\d\z/)
      end

      def cors_config
        <<~XML
          <CORSConfiguration>
           <CORSRule>
            <AllowedOrigin>https://#{APP_ORIGIN_HOST}</AllowedOrigin>
            <AllowedMethod>PUT</AllowedMethod>
            <AllowedMethod>GET</AllowedMethod>
            <AllowedMethod>HEAD</AllowedMethod>
            <AllowedHeader>*</AllowedHeader>
            <ExposeHeader>ETag</ExposeHeader>
            <MaxAgeSeconds>3000</MaxAgeSeconds>
           </CORSRule>
          </CORSConfiguration>
        XML
      end

      attr_reader :runner, :shell

      def storage_run_command
        [
          "docker run --rm --detach",
          "--name #{STORAGE_CONTAINER}",
          "--publish #{S3_PORT}:8333",
          "--publish #{WEB_UI_PORT}:8888",
          "--network #{Services::NETWORK_NAME}",
          "--volume #{STORAGE_VOLUME}:/data",
          STORAGE_IMAGE,
          SERVER_ARGS.join(" ")
        ]
      end
    end
  end
end
