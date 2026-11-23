#!/usr/bin/env ruby

require "fileutils"
require "thor"

module AppCLI
  module Services
    # Finds the host files a checkout's app container needs and prepares its
    # bind-mount targets.
    #
    # `config/master.key` and `.env.<env>` are gitignored, so a fresh worktree has
    # neither. They are read from the target checkout when present, otherwise from
    # the main checkout. They are never copied or written into the target.
    class MountSources
      # Directories the container writes into. Created up front, as the host
      # user, so nothing in the checkout ends up root-owned or Docker-created.
      MOUNT_DIRS = %w[tmp log].freeze

      def initialize(checkout_path:, main_path:)
        @checkout_path = checkout_path
        @main_path = main_path
      end

      def master_key_path
        path = locate("config/master.key")
        raise Thor::Error, missing_key_message unless path

        # `$(cat …)` of an empty key starts the app without one.
        raise Thor::Error, "#{path} is empty. Please add the key before starting the app." if File.empty?(path)

        path
      end

      # @return [String, nil] nil when no checkout has the file (it is optional)
      def env_file_path(rails_env)
        locate(".env.#{rails_env}")
      end

      def prepare!
        MOUNT_DIRS.each do |dir|
          target = File.join(checkout_path, dir)
          raise Thor::Error, "#{target} is a file; it must be a directory. Remove it and retry." if File.file?(target)

          FileUtils.mkdir_p(target)
        end
      end

      private

      attr_reader :checkout_path, :main_path

      # Every file found is read on the host when the container starts
      # (`$(cat …)`, `--env-file`), so an unreadable one is refused here, before
      # anything is stopped or started.
      def locate(relative)
        candidates = [checkout_path, main_path].uniq.map { |root| File.join(root, relative) }
        candidates.each { |path| refuse_directory!(path) }
        path = candidates.find { |candidate| File.file?(candidate) }
        refuse_unreadable!(path) if path
        path
      end

      def refuse_unreadable!(path)
        return if File.readable?(path)

        raise Thor::Error, "#{path} is not readable by #{ENV.fetch("USER", "this user")}. Fix its permissions and retry."
      end

      # Docker creates a missing bind-mount source as an empty directory, so a
      # stray directory where a file belongs is a leftover of an earlier run.
      def refuse_directory!(path)
        return unless File.directory?(path)

        raise Thor::Error,
              "#{path} is a directory, but it must be a file (Docker probably created it). " \
              "Remove it with `rmdir #{path}` and retry."
      end

      def missing_key_message
        "Missing config/master.key in #{checkout_path}" \
          "#{" and #{main_path}" unless same_checkout?}. Please add it before starting the app."
      end

      def same_checkout?
        File.expand_path(checkout_path) == File.expand_path(main_path)
      end
    end
  end
end
