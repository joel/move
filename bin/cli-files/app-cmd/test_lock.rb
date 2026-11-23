#!/usr/bin/env ruby

require "fileutils"
require "time"
require "thor"

module AppCLI
  module Services
    # A host-wide, non-blocking flock on a file in the main checkout's tmp/.
    # It serialises `bin/cli app test` runs (every worktree shares one test
    # database) and, with its own file, `app start`/`stop`/`restart` (every
    # worktree shares the move-app-dev container names).
    #
    # The holder writes its pid, checkout and branch into the file so a refused
    # run can say who holds it. The kernel drops the flock when the holder dies,
    # so a crash never leaves a stale lock behind.
    class TestLock
      DEFAULT_BUSY = "Another `bin/cli app test` is running".freeze

      # @param busy [String] the start of the refusal message, before "(<holder>)"
      def initialize(path:, busy: DEFAULT_BUSY)
        @path = path
        @busy = busy
      end

      def synchronize(holder)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::RDWR | File::CREAT, 0o644) do |file|
          raise Thor::Error, busy_message(file) unless file.flock(File::LOCK_EX | File::LOCK_NB)

          begin
            record(file, holder)
            yield
          ensure
            file.truncate(0)
            file.flock(File::LOCK_UN)
          end
        end
      end

      private

      attr_reader :path, :busy

      def record(file, holder)
        file.truncate(0)
        file.rewind
        file.write("pid #{Process.pid}, #{holder}, started #{Time.now.utc.iso8601}\n")
        file.flush
      end

      def busy_message(file)
        holder = file.read.to_s.strip
        holder = "unknown holder" if holder.empty?
        "#{busy} (#{holder}). Wait for it to finish; lock: #{path}"
      end
    end
  end
end
