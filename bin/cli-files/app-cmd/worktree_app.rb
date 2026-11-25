#!/usr/bin/env ruby

require "shellwords"
require "thor"
require_relative "../services/helpers"

module AppCLI
  module Services
    # The names of one served worktree app (`bin/cli app serve`), all derived
    # from one label `<wt>`:
    #
    # - container   move-app-wt-<wt>
    # - zone        <wt>.wt.move-easy.docker (apex move.<zone>, orgs <slug>.<zone>)
    # - database    move_development_wt_<wt> (hyphens become underscores)
    #
    # The label comes from --name, or else from the checkout's directory name.
    # config/dev_worktree.rb applies the same rules on the Rails side.
    class WorktreeApp
      CONTAINER_PREFIX = "#{APP_CONTAINER_BASE}-wt-".freeze
      ZONE_PARENT = "wt.#{DEV_DOMAIN}".freeze
      DATABASE_PREFIX = "#{APP_NAME}_development_wt_".freeze
      MAX_LABEL = 20
      LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,#{MAX_LABEL - 2}}[a-z0-9])?\z/

      attr_reader :label

      # @param name [String, nil] --name; used as is and refused when not a valid label
      def self.for(checkout_path:, name: nil)
        return new(name) if name

        new(sanitize(File.basename(checkout_path.to_s)))
      end

      # Lowercase, every run of other characters becomes one hyphen, trimmed
      # and cut to MAX_LABEL.
      def self.sanitize(raw)
        label = raw.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        label[0, MAX_LABEL].to_s.delete_suffix("-")
      end

      def initialize(label)
        @label = label.to_s
        return if @label.match?(LABEL)

        raise Thor::Error, "#{label.to_s.inspect} is not a usable worktree name: use 1-#{MAX_LABEL} lowercase " \
                           "letters, digits or hyphens, not starting or ending with a hyphen (--name W)."
      end

      def container = "#{CONTAINER_PREFIX}#{label}"
      def zone = "#{label}.#{ZONE_PARENT}"
      def apex = "#{APP_NAME}.#{zone}"
      def url = "https://#{apex}"
      def database = "#{DATABASE_PREFIX}#{label.tr("-", "_")}"

      # The variables config/environments/development.rb and
      # config/database.yml read. WEBAUTHN_RP_ID is the zone, as production
      # uses its apex parent, so a passkey works on the apex and the org hosts.
      def env
        { "MOVE_TENANT_ZONE" => zone, "MOVE_DEV_DATABASE" => database, "WEBAUTHN_RP_ID" => zone }
      end

      def env_flags
        env.map { |key, value| "--env #{key}=#{Shellwords.escape(value)}" }
      end
    end
  end
end
