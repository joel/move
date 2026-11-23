#!/usr/bin/env ruby

require "digest"
require "shellwords"
require_relative "../services/helpers"
require_relative "../db-cmd/db_service"
require_relative "container_flags"
require_relative "mount_sources"
require_relative "test_lock"

module AppCLI
  module Services
    # Throwaway app containers for one checkout: `bin/cli app run`, `app test`
    # and `app console` / `app connect` with `--repo`. They mount the checkout
    # at /rails, join the Docker network and leave the long-lived dev container
    # alone.
    class WorktreeRun
      TEST_CONTAINER = "#{APP_NAME}-app-test".freeze
      LOCK_FILE = "tmp/bin-cli-app-test.lock".freeze
      DEFAULT_TEST_ARGS = ["spec", "--exclude-pattern", "spec/system/**/*_spec.rb"].freeze
      SYSTEM_SPEC_DIR = "spec/system".freeze
      # spec/system itself, a file or dir under it, or a file:line, with an optional leading ./
      SYSTEM_SPEC_PATH = %r{\A(?:\./)?spec/system(?:[/:]|\z)}
      # CI runs the system suite the same way (.github/workflows/ci.yml).
      SYSTEM_ENV = { "TEST_BROWSER" => "rack_test" }.freeze
      # fail_if_no_examples is a config setting, not an rspec flag. The file is
      # written inside the throwaway container, so the checkout needs no copy.
      FAIL_IF_NO_EXAMPLES_FILE = "/tmp/bin-cli-fail-if-no-examples.rb".freeze
      FAIL_IF_NO_EXAMPLES_CODE = "RSpec.configure { |config| config.fail_if_no_examples = true }".freeze
      INTERACTIVE_COMMANDS = { console: %w[bin/rails console], connect: %w[bash] }.freeze
      # Rails db tasks (activerecord/lib/active_record/railties/databases.rake)
      # that change the schema of the shared dev database or wipe its data,
      # with any namespaced variant: `:all`, a database name (`:primary`),
      # `db:migrate:redo`, `db:drop:_unsafe`. db:migrate:status (in any
      # variant) only reads it.
      SCHEMA_TASK = /
        \Adb:
        (?!migrate:status)
        (?:migrate|rollback|forward|schema:load|structure:load|reset|prepare|setup|drop|purge|
           truncate_all|seed:replant|fixtures:load)
        (?::\w+)*
        (?:\[.*\])?\z
      /x
      TASK_RUNNERS = %w[rails rake].freeze
      # Rails commands whose arguments are free-form (code, generator names,
      # options), so a task-shaped word after them is not a task.
      FREE_FORM_COMMAND = /\A(?:runner|r|console|c|generate|g|destroy|d|server|s|dbconsole|db|
                             (?:credentials|encrypted):\w+)\z/x
      # Shell operators that end one command and start the next.
      COMMAND_SEPARATOR = /\A(?:&&|\|\||;|\||&)\z/

      # @param checkout [Checkout] the checkout to mount
      # @param main_path [String] the main checkout (fallback for gitignored files, lock home)
      # @param db [#start] the database service to bring up first
      def initialize(shell:, env:, checkout:, main_path:, runner: nil, db: nil, tty: nil)
        @shell = shell
        @env_config = EnvConfig.new(env)
        refuse_non_dev_env!
        @checkout = checkout
        @main_path = main_path
        @runner = runner || CommandRunner.new(shell: shell)
        @db = db || DbService.new(shell: shell, env: env)
        @tty = tty.nil? ? { stdin: $stdin.tty?, stdout: $stdout.tty? } : tty
      end

      # @param keep_stdin [Boolean] attach stdin even when it is not a TTY
      # @param confirmed [Boolean] --yes: run a schema-changing task from a worktree anyway
      # @return [Integer] the command's exit status
      def run(command_parts, keep_stdin: false, confirmed: false)
        raise Thor::Error, "No command given. Usage: bin/cli app run [--repo T] -- CMD..." if command_parts.empty?

        announce(shared_db: true)
        confirm_schema_change!(command_parts, confirmed)
        prepare
        runner.run_status(docker_run(command_parts, rails_env: env_config.env, keep_stdin: keep_stdin))
      end

      # An interactive Rails console (:console) or shell (:connect) in a
      # throwaway container for the checkout. stdin is always attached, so a
      # script can be piped in; a tty only when both ends are terminals.
      # @return [Integer] the session's exit status
      def interactive(kind)
        run(INTERACTIVE_COMMANDS.fetch(kind), keep_stdin: true)
      end

      # @param system [Boolean] run spec/system under rack_test instead of the unit suite
      # @return [Integer] rspec's exit status
      def test(rspec_args, system: false)
        announce
        TestLock.new(path: File.join(main_path, LOCK_FILE)).synchronize(checkout.describe) do
          refuse_leftover_container!
          prepare
          args = system ? system_args(rspec_args) : unit_args(rspec_args)
          script = "bin/rails db:test:prepare && bundle exec rspec #{Shellwords.join(args)}"
          script = "#{fail_if_no_examples_prelude} && #{script}" if args.include?(FAIL_IF_NO_EXAMPLES_FILE)
          extra_env = system ? SYSTEM_ENV : {}
          runner.run_status(docker_run(["bash", "-c", script], rails_env: "test", name: TEST_CONTAINER,
                                                               extra_env: extra_env))
        end
      end

      def docker_run(command_parts, rails_env:, name: nil, extra_env: {}, keep_stdin: false)
        [
          "docker run --rm",
          *tty_flags(keep_stdin: keep_stdin),
          *("--name #{name}" if name),
          *flags.network,
          *flags.env(rails_env),
          *extra_env.map { |key, value| "--env #{key}=#{Shellwords.escape(value)}" },
          *flags.volumes,
          env_config.app_image,
          Shellwords.join(command_parts)
        ]
      end

      private

      attr_reader :shell, :env_config, :checkout, :main_path, :runner, :db, :tty

      # Only the dev image runs mounted code. The prod image runs its baked-in
      # build (precompiled assets, production-only bundle), so a mounted
      # checkout would not match it. Refuse instead of silently running the
      # image's revision.
      def refuse_non_dev_env!
        return if env_config.short == "dev"

        raise Thor::Error,
              "bin/cli app run/test (and console/connect with --repo) only supports the dev environment: it mounts a checkout, " \
              "and the #{env_config.env} image runs its built-in code. " \
              "Use `bin/cli app exec #{env_config.short} ...` for the production image."
      end

      # run/console/connect use the dev database of move-app-dev; test uses move_test.
      def announce(shared_db: false)
        shell.say("Running in #{checkout.describe}")
        shell.say("Database: #{env_config.db_names.first} (shared with #{env_config.app_container})") if shared_db
      end

      # A worktree's migrations would change the schema main's dev app runs on
      # (and its db/structure.sql dump), so ask for --yes first.
      def confirm_schema_change!(command_parts, confirmed)
        return if checkout.main?

        task = schema_task(command_parts)
        return unless task

        shell.say("Warning: #{task} changes the schema or data of #{env_config.db_names.first}, " \
                  "which #{env_config.app_container} uses too.")
        return if confirmed

        raise Thor::Error, "Refusing to run #{task} from #{checkout.describe} without --yes. " \
                           "Re-run as `bin/cli app run --repo #{checkout.path} --yes -- #{Shellwords.join(command_parts)}`."
      end

      # The first gated task given to `rails`/`rake` (bin/, bundle exec and
      # `bash -c "…"` included). A task name that is only an argument of some
      # other command (`echo db:migrate`, `rg db:migrate doc`), or of a
      # free-form Rails command (`rails runner 'puts "db:migrate"'`), does not
      # count. Several tasks in one call (`rake db:seed db:migrate`) are all seen.
      def schema_task(command_parts)
        scanning = false
        shell_tokens(command_parts).each do |token|
          if ends_scan?(token, scanning)
            scanning = false # until the next rails/rake
          elsif TASK_RUNNERS.include?(File.basename(token))
            scanning = true
          elsif scanning && token.match?(SCHEMA_TASK)
            return token
          end
        end
        nil
      end

      # A new command starts, or `rails`/`rake` got a free-form command.
      def ends_scan?(token, scanning)
        token.match?(COMMAND_SEPARATOR) || (scanning && token.match?(FREE_FORM_COMMAND))
      end

      # Each argument is split shell-style too, so `bash -c "bin/rails db:migrate && …"`
      # is seen as its own commands; operators glued to a word (`db:migrate;`) are split off.
      def shell_tokens(command_parts)
        command_parts.flat_map { |part| split_words(part) }
                     .flat_map { |word| word.split(/(&&|\|\||;|\||&)/) }
                     .reject(&:empty?)
      end

      def split_words(part)
        Shellwords.split(part)
      rescue ArgumentError # unbalanced quotes: fall back to whitespace
        part.split
      end

      def prepare
        sources.master_key_path
        sources.prepare!
        unless runner.image_exists?(env_config.app_image)
          raise Thor::Error, "App image #{env_config.app_image} is missing. Build it with `bin/cli app build`."
        end

        warn_gemfile_drift
        runner.ensure_network(env_config.network_name)
        db.start
      end

      def unit_args(rspec_args)
        rspec_args.empty? ? DEFAULT_TEST_ARGS : rspec_args
      end

      # spec/system unless the caller already named system spec paths. :js
      # specs switch to headless Chrome, which needs chromedriver in the image.
      # When the caller named the specs, a run that filters all of them out
      # must fail rather than pass with 0 examples.
      def system_args(rspec_args)
        explicit = rspec_args.any?(SYSTEM_SPEC_PATH)
        args = explicit ? rspec_args : [SYSTEM_SPEC_DIR, *rspec_args]
        return args if chromedriver?

        shell.say("chromedriver is not in #{env_config.app_image}: skipping :js system specs (--tag ~js); " \
                  "they run in CI only.")
        return [*args, "--tag", "~js"] unless explicit

        shell.say("If every named spec is :js, the run fails with no examples (fail_if_no_examples).")
        [*args, "--tag", "~js", "--require", FAIL_IF_NO_EXAMPLES_FILE]
      end

      def fail_if_no_examples_prelude
        "echo #{Shellwords.escape(FAIL_IF_NO_EXAMPLES_CODE)} > #{FAIL_IF_NO_EXAMPLES_FILE}"
      end

      def chromedriver?
        !runner.capture("docker run --rm --entrypoint sh #{env_config.app_image} -c 'command -v chromedriver'",
                        quiet: true).nil?
      end

      def refuse_leftover_container!
        return if runner.container_status(TEST_CONTAINER) == "missing"

        raise Thor::Error,
              "Container #{TEST_CONTAINER} already exists, probably left by an earlier run. " \
              "Remove it with `docker rm -f #{TEST_CONTAINER}` and retry."
      end

      def warn_gemfile_drift
        local = File.join(checkout.path, "Gemfile.lock")
        return unless File.file?(local)

        output = runner.capture("docker run --rm --entrypoint sha256sum #{env_config.app_image} /rails/Gemfile.lock",
                                quiet: true)
        return if output.nil? || output.split.first == Digest::SHA256.file(local).hexdigest

        shell.say("Warning: #{local} differs from the one in #{env_config.app_image}; " \
                  "the image's gems may not match. Run `bin/cli app build` if gems changed.")
      end

      def tty_flags(keep_stdin: false)
        flags = []
        flags << "--interactive" if keep_stdin || tty[:stdin]
        flags << "--tty" if tty[:stdin] && tty[:stdout]
        flags
      end

      def sources
        @sources ||= MountSources.new(checkout_path: checkout.path, main_path: main_path)
      end

      def flags
        @flags ||= ContainerFlags.new(env_config: env_config, checkout_path: checkout.path, sources: sources)
      end
    end
  end
end
