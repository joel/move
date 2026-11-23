require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/services/services_manager"

# Records docker commands instead of running them, and models the containers
# they touch: the app container starts out running. `boots` decides, per
# container name at `docker start`/`run`, whether it answers /up.
class FakeAppRunner
  # What each docker command does to the modelled containers.
  TRANSITIONS = {
    /\Adocker create .*--name (\S+)/ => ->(m) { containers[m[1]] = "created" },
    /\Adocker run --detach .*--name (\S+)/ => ->(m) { containers[m[1]] = started(m[1]) },
    /\Adocker start (\S+)\z/ => ->(m) { containers[m[1]] = started(m[1]) },
    /\Adocker stop (\S+)\z/ => ->(m) { containers[m[1]] = auto_remove ? "removing" : "exited" },
    /\Adocker rename (\S+) (\S+)\z/ => ->(m) { containers[m[2]] = containers.delete(m[1]) },
    /\Adocker rm (?:--force )?(\S+)\z/ => ->(m) { containers.delete(m[1]) unless containers[m[1]] == "removing" }
  }.freeze

  attr_reader :commands, :containers
  attr_accessor :image_present, :bundle_satisfied, :boots, :auto_remove, :removal_lag, :up_status

  def initialize
    @commands = []
    @image_present = true
    @bundle_satisfied = true
    @containers = { "move-app-dev" => "running" }
    @ready = {}
    @boots = ->(_name) { true }
    @auto_remove = false
    @removal_lag = 0
    @up_status = nil # HTTP status of /up for a container that boots; nil means "200"
  end

  # Kernel.system-style: false only for a failing `bundle check`.
  def run(command, **)
    line = Array(command).join(" ")
    @commands << line
    return bundle_satisfied if line.end_with?("bundle check")

    simulate(line)
    true
  end

  def capture(command, **)
    @commands << command
    return AppCLI::Services::EnvConfig.new("development").ruby_version if command.include?("RUBY_VERSION")
    return auto_remove.to_s if command.include?("AutoRemove")
    return "/checkouts/old" if command.include?("Mounts")
    return probe(Regexp.last_match(1)) if command =~ /\Adocker exec (\S+) curl/

    "boot log line\n#{"\tfrom /rails/bin/rails:4:in '<main>'\n" * 50}" if command.start_with?("docker logs")
  end

  def image_exists?(_image) = image_present
  def container_running?(name) = container_status(name) == "running"

  # A --rm container shows as "exited" for `removal_lag` polls after its stop.
  def container_status(name)
    status = containers[name] || "missing"
    return status unless status == "removing"
    return "exited" if (self.removal_lag -= 1) >= 0

    containers.delete(name)
    "missing"
  end

  def ensure_network(_name) = nil

  private

  # curl --write-out '%{http_code}' prints 000 when nothing answers.
  def probe(name) = @ready.fetch(name, false) ? up_status || "200" : "000"

  def simulate(line)
    TRANSITIONS.each do |pattern, effect|
      match = pattern.match(line)
      next unless match

      instance_exec(match, &effect)
      break
    end
  end

  def started(name)
    @ready[name] = boots.call(name)
    "running"
  end
end

RSpec.describe AppCLI::Services::AppService do
  subject(:service) do
    described_class.new(shell: shell, env: "development", runner: runner, checkout_path: worktree, main_path: main)
  end

  let(:tmp) { Dir.mktmpdir("appsvc") }
  let(:shell) { instance_double(Thor::Shell::Basic, say: nil, say_status: nil) }
  let(:runner) { FakeAppRunner.new }

  def main = File.join(tmp, "main")
  def worktree = File.join(tmp, "wt")
  # Commands that take the running app container down.
  def stops = runner.commands.grep(/\Adocker (stop|rm|rename) move-app-dev\b/)

  before do
    stub_const("AppCLI::Services::ReadinessCheck::POLL_INTERVAL", 0)
    FileUtils.mkdir_p([File.join(main, "config"), File.join(worktree, "config")])
  end

  after { FileUtils.remove_entry(tmp) }

  describe "#preflight" do
    it "fails before any docker call when neither checkout has config/master.key" do
      expect { service.preflight }.to raise_error(Thor::Error, %r{Missing config/master.key in #{worktree} and #{main}})
      expect(runner.commands).to be_empty
    end

    it "refuses a .env file that is a directory before any docker call" do
      File.write(File.join(main, "config/master.key"), "k")
      FileUtils.mkdir_p(File.join(worktree, ".env.development"))

      expect { service.preflight }.to raise_error(Thor::Error, %r{#{worktree}/.env.development is a directory})
      expect(runner.commands).to be_empty
    end

    it "accepts the main checkout's key when the worktree has none" do
      File.write(File.join(main, "config/master.key"), "k")
      expect { service.preflight }.not_to raise_error
    end
  end

  describe "#start" do
    before do
      File.write(File.join(main, "config/master.key"), "k")
      runner.containers.clear
    end

    it "mounts the worktree and reads the key and .env file from the main checkout" do
      File.write(File.join(main, ".env.development"), "A=1")

      service.start

      command = runner.commands.find { |c| c.start_with?("docker run --detach") }
      expect(command).to include("--volume #{worktree}:/rails", "RAILS_MASTER_KEY=$(cat #{main}/config/master.key)",
                                 "--env-file #{main}/.env.development")
      expect(runner.commands).to include(a_string_matching(%r{\Adocker exec move-app-dev curl .*localhost:9292/up}))
    end

    it "prefers the worktree's own key" do
      File.write(File.join(worktree, "config/master.key"), "w")

      service.start

      expect(runner.commands.join("\n")).to include("RAILS_MASTER_KEY=$(cat #{worktree}/config/master.key)")
    end

    it "fails with the container's last log lines, and removes it, when it never answers /up" do
      runner.boots = ->(_name) { false }
      stub_const("AppCLI::Services::ReadinessCheck::DEFAULT_TIMEOUT", 0)

      expect { service.start }.to raise_error(Thor::Error, %r{did not answer /up.*boot log line.*Nothing is running now}m)
      expect(runner.containers).to be_empty
    end

    it "replaces an exited app container left behind instead of conflicting with its name" do
      runner.containers["move-app-dev"] = "exited"

      service.start

      expect(runner.commands.index("docker rm --force move-app-dev"))
        .to be < runner.commands.index { |c| c.start_with?("docker run --detach") }
      expect(runner.containers).to eq("move-app-dev" => "running")
    end

    it "refuses to start next to a stale -prev container" do
      runner.containers["move-app-dev-prev"] = "exited"

      expect { service.start }.to raise_error(Thor::Error, /move-app-dev-prev .* docker rename move-app-dev-prev/)
      expect(runner.commands).not_to include(a_string_starting_with("docker run --detach"))
    end
  end

  describe "#stop" do
    it "removes the stopped container" do
      service.stop

      expect(runner.commands).to eq(["docker stop move-app-dev", "docker rm move-app-dev"])
      expect(runner.containers).to be_empty
    end

    it "waits for Docker to remove a --rm container (started before #879)" do
      runner.auto_remove = true
      runner.removal_lag = 2
      stub_const("#{described_class}::REMOVAL_POLL_INTERVAL", 0)

      service.stop

      expect(runner.containers).to be_empty
      expect(runner.commands).not_to include("docker rm --force move-app-dev")
    end

    it "removes a container that outlives the wait, and refuses to go on if it is still there" do
      runner.auto_remove = true
      runner.removal_lag = described_class::REMOVAL_POLLS + 5
      stub_const("#{described_class}::REMOVAL_POLL_INTERVAL", 0)

      expect { service.stop }.to raise_error(Thor::Error, /move-app-dev is still there after `docker stop`/)
      expect(runner.commands).to include("docker rm --force move-app-dev")
    end
  end

  describe "ServicesManager#restart_app" do
    let(:manager) { AppCLI::Services::ServicesManager.new(shell: shell, env: "development") }

    before do
      manager.instance_variable_set(:@app, service)
      allow(manager).to receive(:start_dependencies)
    end

    # Every input the restart depends on, broken one at a time.
    def fail_on(prefix, message)
      allow(runner).to receive(:run).and_wrap_original do |original, command, **opts|
        raise Thor::Error, message if Array(command).join(" ").start_with?(prefix)

        original.call(command, **opts)
      end
    end

    def unreadable(path)
      allow(File).to receive(:readable?).and_call_original
      allow(File).to receive(:readable?).with(path).and_return(false)
    end

    def key(root) = File.join(root, "config/master.key")
    def env(root) = File.join(root, ".env.development")

    broken_inputs = {
      "no master.key anywhere" => -> { FileUtils.rm_f(key(main)) },
      "a blank master.key" => -> { File.write(key(main), "\n") },
      "an unreadable master.key" => -> { unreadable(key(main)) },
      "a directory where the worktree's master.key belongs" => -> { FileUtils.mkdir_p(key(worktree)) },
      "a directory where .env.development belongs" => -> { FileUtils.mkdir_p(env(main)) },
      "an unreadable .env.development" => lambda {
        File.write(env(main), "A=1")
        unreadable(env(main))
      },
      "a missing checkout (the /rails volume source)" => -> { FileUtils.rm_rf(worktree) },
      "the Docker network can't be created" => lambda {
        allow(runner).to receive(:ensure_network).and_raise(Thor::Error, "network")
      },
      "a missing image whose build fails" => lambda {
        runner.image_present = false
        fail_on("docker build", "build")
      },
      "an image with the wrong Ruby whose rebuild fails" => lambda {
        allow(runner).to receive(:capture).and_return("0.0.1")
        fail_on("docker build", "build")
      },
      "image gems that don't satisfy the Gemfile.lock" => -> { runner.bundle_satisfied = false },
      "a dependency (router/db/storage) that fails to start" => lambda {
        allow(manager).to receive(:start_dependencies).and_raise(Thor::Error, "db")
      },
      "Docker rejecting the replacement (e.g. invalid --env-file)" => -> { fail_on("docker create", "invalid env") },
      "a #{AppCLI::Services::ReadinessCheck::TIMEOUT_ENV} that is not a number" => lambda {
        stub_const("ENV", ENV.to_h.merge(AppCLI::Services::ReadinessCheck::TIMEOUT_ENV => "soon"))
      },
      "a stale move-app-dev-prev from an interrupted restart" => -> { runner.containers["move-app-dev-prev"] = "exited" }
    }

    broken_inputs.each do |input, break_it|
      it "issues no docker stop or rm, and leaves move-app-dev serving, on #{input}" do
        File.write(key(main), "k")
        instance_exec(&break_it)

        expect { manager.restart_app }.to raise_error(Thor::Error)
        expect(runner.commands.grep(/\Adocker (stop|rm|rename|start)\b/)).to be_empty
        expect(runner.containers["move-app-dev"]).to eq("running")
      end
    end

    it "fails before stopping the running app container when no master key is found" do
      expect { manager.restart_app }.to raise_error(Thor::Error, %r{Missing config/master.key})
      expect(stops).to be_empty
      expect(manager).not_to have_received(:start_dependencies)
    end

    it "keeps the old container as -prev until the replacement answers /up, then removes it" do
      File.write(File.join(main, "config/master.key"), "k")

      manager.restart_app

      steps = [/RUBY_VERSION/, /bundle check\z/, /\Adocker create --name move-app-dev-next /,
               /\Adocker rename move-app-dev move-app-dev-prev\z/, /\Adocker stop move-app-dev-prev\z/,
               /\Adocker rename move-app-dev-next move-app-dev\z/, /\Adocker start move-app-dev\z/,
               /\Adocker exec move-app-dev curl/, /\Adocker rm move-app-dev-prev\z/]
      positions = steps.map { |step| runner.commands.index { |c| c.match?(step) } }
      expect(positions).to all(be_an(Integer))
      expect(positions).to eq(positions.sort)
      create = runner.commands.find { |c| c.start_with?("docker create") }
      expect(create).to include("RAILS_MASTER_KEY=$(cat #{main}/config/master.key)", "--volume #{worktree}:/rails",
                                "--publish 8080:9292", "bin/rails s -p 9292 -b 0.0.0.0")
      expect(runner.containers).to eq("move-app-dev" => "running") # nothing from `docker run`, no -prev
      expect(manager).to have_received(:start_dependencies)
      expect(runner.commands.grep(/bundle check|RUBY_VERSION/).size).to eq(2) # once each, before the stop
    end

    context "when the replacement never answers /up" do
      before do
        File.write(File.join(main, "config/master.key"), "k")
        runner.boots = ->(_name) { !runner.containers.key?("move-app-dev-prev") }
        stub_const("AppCLI::Services::ReadinessCheck::DEFAULT_TIMEOUT", 0)
      end

      it "removes it, brings the old container back, and fails with the replacement's logs" do
        expect { manager.restart_app }
          .to raise_error(Thor::Error, %r{did not answer /up.*boot log line.*previous move-app-dev is back and serving}m)

        steps = ["docker start move-app-dev", "docker rm --force move-app-dev",
                 "docker rename move-app-dev-prev move-app-dev", "docker start move-app-dev"]
        start = runner.commands.index(steps.first)
        expect(runner.commands[start..].grep(/\Adocker (start|rm|rename)/)).to eq(steps)
        expect(runner.containers).to eq("move-app-dev" => "running")
      end

      it "removes the server.pid the replacement may have left in the old container's checkout" do
        allow(FileUtils).to receive(:rm_f).and_call_original

        expect { manager.restart_app }.to raise_error(Thor::Error)
        expect(FileUtils).to have_received(:rm_f).with("/checkouts/old/tmp/pids/server.pid")
      end

      it "keeps the exception message when the backtrace is longer than the tail" do
        expect { manager.restart_app }.to raise_error(Thor::Error) { |e| expect(e.message).not_to include("from /rails") }
      end

      it "says so when the old container doesn't come back either" do
        runner.boots = ->(_name) { false }

        expect { manager.restart_app }.to raise_error(Thor::Error, %r{did not answer /up either})
        expect(runner.containers).to eq("move-app-dev" => "running")
      end
    end

    it "fails without a rollback when the old container ran with --rm (started before #879)" do
      File.write(File.join(main, "config/master.key"), "k")
      runner.auto_remove = true
      runner.boots = ->(_name) { false }
      stub_const("AppCLI::Services::ReadinessCheck::DEFAULT_TIMEOUT", 0)

      expect { manager.restart_app }.to raise_error(Thor::Error, /No previous container was kept/)
      expect(runner.commands).not_to include(a_string_matching(/move-app-dev-prev/))
      expect(runner.containers).to be_empty
    end

    it "rolls back when the replacement can't even be started" do
      File.write(File.join(main, "config/master.key"), "k")
      allow(runner).to receive(:run).and_wrap_original do |original, command, **opts|
        line = Array(command).join(" ")
        raise Thor::Error, "port is already allocated" if line == "docker start move-app-dev" &&
                                                          runner.containers.key?("move-app-dev-prev")

        original.call(command, **opts)
      end

      expect { manager.restart_app }.to raise_error(Thor::Error, /previous move-app-dev is back/)
      expect(runner.containers).to eq("move-app-dev" => "running")
    end

    it "points at the cleanup for a stale -prev while move-app-dev is running" do
      runner.containers["move-app-dev-prev"] = "exited"
      File.write(File.join(main, "config/master.key"), "k")

      expect { manager.restart_app }
        .to raise_error(Thor::Error, %r{interrupted `bin/cli app restart`.*works, drop the old one: `docker rm --force move-app-dev-prev`.*To go back})
    end

    it "leaves the old container up when Docker rejects the replacement" do
      File.write(File.join(main, "config/master.key"), "k")
      fail_on("docker create", "invalid env file")

      expect { manager.restart_app }.to raise_error(Thor::Error, "invalid env file")
      expect(stops).to be_empty
    end

    it "refuses a checkout whose Gemfile.lock the image's gems don't satisfy, before stopping" do
      File.write(File.join(main, "config/master.key"), "k")
      runner.bundle_satisfied = false

      expect { manager.restart_app }.to raise_error(Thor::Error, /gems in .* don't match #{worktree}/)
      expect(runner.commands).to include(a_string_matching(%r{--volume #{worktree}:/rails .* bundle check\z}))
      expect(stops).to be_empty
    end
  end

  describe "the host-wide restart lock" do
    let(:lock_path) { File.join(main, "tmp/app-restart.lock") }
    let(:holder) { AppCLI::Services::TestLock.new(path: lock_path, busy: "x") }

    before { File.write(File.join(main, "config/master.key"), "k") }

    %i[replace start stop].each do |command|
      it "refuses a second caller of ##{command} while another holds the lock, before any docker call" do
        holder.synchronize("/checkouts/other (branch b)") do
          expect { service.public_send(command) }.to raise_error(
            Thor::Error, %r{another restart is in progress \(pid \d+, /checkouts/other \(branch b\), started }
          )
        end
        expect(runner.commands).to be_empty
      end
    end

    it "names its own holder (pid, checkout, branch, start time) while it runs" do
      seen = nil
      allow(runner).to receive(:run).and_wrap_original do |original, command, **opts|
        seen ||= File.read(lock_path) if Array(command).join(" ").start_with?("docker create")
        original.call(command, **opts)
      end
      service.replace

      expect(seen).to match(/\Apid #{Process.pid}, #{Regexp.escape(worktree)} \(branch \S+\), started \d{4}-/)
      expect(File.read(lock_path)).to be_empty
    end

    it "lets a restart that stops a --rm container (a nested #stop) through its own lock" do
      runner.auto_remove = true
      expect { service.replace }.not_to raise_error
      expect(runner.containers).to eq("move-app-dev" => "running")
    end
  end

  describe AppCLI::Services::ReadinessCheck do
    let(:check) do
      described_class.new(runner: runner, shell: instance_double(Thor::Shell::Basic, say: nil), timeout: 0)
    end

    it "is ready on a 2xx from /up" do
      runner.containers["move-app-next"] = "running"
      runner.send(:started, "move-app-next")
      runner.up_status = "204"
      expect(check.ready?("move-app-next")).to be(true)
    end

    it "is not ready on a 302 from /up (curl --fail passes any 3xx)" do
      runner.containers["move-app-next"] = "running"
      runner.send(:started, "move-app-next")
      runner.up_status = "302"
      expect(check.ready?("move-app-next")).to be(false)
      expect(runner.commands.last).to include("--write-out '%{http_code}'") # rubocop:disable Style/FormatStringToken -- curl syntax
    end

    it "defaults to 60 seconds and reads MOVE_APP_READY_TIMEOUT" do
      expect(described_class.timeout({})).to eq(60)
      expect(described_class.timeout("MOVE_APP_READY_TIMEOUT" => "120")).to eq(120)
    end

    it "refuses a timeout that is not a positive whole number" do
      %w[0 -5 1.5 soon].each do |raw|
        expect { described_class.timeout("MOVE_APP_READY_TIMEOUT" => raw) }.to raise_error(Thor::Error, /whole number/)
      end
    end

    it "gives up as soon as the container stops, without waiting out the timeout" do
      runner = FakeAppRunner.new
      runner.containers["move-app-dev"] = "exited"
      check = described_class.new(runner: runner, shell: instance_double(Thor::Shell::Basic, say: nil), timeout: 600)

      expect(check.ready?("move-app-dev")).to be(false)
      expect(runner.commands).to be_empty
    end
  end
end
