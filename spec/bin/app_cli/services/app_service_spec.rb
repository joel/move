require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/services/services_manager"

# Records docker commands instead of running them; the app container starts out running.
class FakeAppRunner
  attr_reader :commands
  attr_accessor :image_present, :bundle_satisfied, :statuses

  def initialize
    @commands = []
    @image_present = true
    @bundle_satisfied = true
    @statuses = []
  end

  # Kernel.system-style: false only for a failing `bundle check`.
  def run(command, **)
    line = Array(command).join(" ")
    @commands << line
    bundle_satisfied || !line.end_with?("bundle check")
  end

  def capture(command, **)
    @commands << command
    command.include?("RUBY_VERSION") ? AppCLI::Services::EnvConfig.new("development").ruby_version : nil
  end

  def image_exists?(image) = image_present || image.include?("wait")
  def container_running?(_name) = true
  # Scripted `docker inspect` answers after a stop; "missing" once they run out.
  def container_status(_name) = statuses.shift || "missing"
  def ensure_network(_name) = nil
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
  def stops = runner.commands.grep(/\Adocker (stop|rm --force) move-app-dev\z/)

  before { FileUtils.mkdir_p([File.join(main, "config"), File.join(worktree, "config")]) }
  after { FileUtils.remove_entry(tmp) }

  describe "#prepare" do
    it "fails before any docker call when neither checkout has config/master.key" do
      expect { service.prepare }.to raise_error(Thor::Error, %r{Missing config/master.key in #{worktree} and #{main}})
      expect(runner.commands).to be_empty
    end

    it "refuses a .env file that is a directory before any docker call" do
      File.write(File.join(main, "config/master.key"), "k")
      FileUtils.mkdir_p(File.join(worktree, ".env.development"))

      expect { service.prepare }.to raise_error(Thor::Error, %r{#{worktree}/.env.development is a directory})
      expect(runner.commands).to be_empty
    end

    it "accepts the main checkout's key when the worktree has none" do
      File.write(File.join(main, "config/master.key"), "k")
      expect { service.prepare }.not_to raise_error
    end
  end

  describe "#start" do
    before { File.write(File.join(main, "config/master.key"), "k") }

    it "mounts the worktree and reads the key and .env file from the main checkout" do
      File.write(File.join(main, ".env.development"), "A=1")
      allow(runner).to receive(:container_running?).and_return(false)

      service.start

      command = runner.commands.find { |c| c.start_with?("docker run --rm --detach") }
      expect(command).to include("--volume #{worktree}:/rails", "RAILS_MASTER_KEY=$(cat #{main}/config/master.key)",
                                 "--env-file #{main}/.env.development")
    end

    it "prefers the worktree's own key" do
      File.write(File.join(worktree, "config/master.key"), "w")
      allow(runner).to receive(:container_running?).and_return(false)

      service.start

      expect(runner.commands.join("\n")).to include("RAILS_MASTER_KEY=$(cat #{worktree}/config/master.key)")
    end
  end

  describe "ServicesManager#restart_app" do
    let(:manager) { AppCLI::Services::ServicesManager.new(shell: shell, env: "development") }

    def stop_running_on_stop
      running = true
      allow(runner).to receive(:container_running?) { running }
      allow(runner).to receive(:run).and_wrap_original do |original, command, **opts|
        running = false if Array(command).join(" ").start_with?("docker stop")
        original.call(command, **opts)
      end
    end

    before do
      manager.instance_variable_set(:@app, service)
      allow(manager).to receive(:start_dependencies)
    end

    it "fails before stopping the running app container when no master key is found" do
      expect { manager.restart_app }.to raise_error(Thor::Error, %r{Missing config/master.key})
      expect(stops).to be_empty
      expect(manager).not_to have_received(:start_dependencies)
    end

    it "creates the replacement before stopping the old container, then swaps it in" do
      File.write(File.join(main, "config/master.key"), "k")
      stop_running_on_stop

      manager.restart_app

      steps = [/RUBY_VERSION/, /bundle check\z/, /\Adocker create --rm --name move-app-dev-next /,
               /\Adocker stop move-app-dev\z/, /\Adocker rename move-app-dev-next move-app-dev\z/,
               /\Adocker start move-app-dev\z/]
      positions = steps.map { |step| runner.commands.index { |c| c.match?(step) } }
      expect(positions).to all(be_an(Integer))
      expect(positions).to eq(positions.sort)
      create = runner.commands.find { |c| c.start_with?("docker create") }
      expect(create).to include("RAILS_MASTER_KEY=$(cat #{main}/config/master.key)", "--volume #{worktree}:/rails",
                                "--publish 8080:9292", "bin/rails s -p 9292 -b 0.0.0.0")
      expect(runner.commands).not_to include(a_string_starting_with("docker run --rm --detach"))
      expect(manager).to have_received(:start_dependencies)
      expect(runner.commands.grep(/bundle check|RUBY_VERSION/).size).to eq(2) # once each, before the stop
    end

    it "leaves the old container up when Docker rejects the replacement" do
      File.write(File.join(main, "config/master.key"), "k")
      stop_running_on_stop
      allow(runner).to receive(:run).and_wrap_original do |original, command, **opts|
        raise Thor::Error, "invalid env file" if Array(command).join(" ").start_with?("docker create")

        original.call(command, **opts)
      end

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

    it "waits for Docker to remove the stopped container before starting the new one" do
      File.write(File.join(main, "config/master.key"), "k")
      runner.statuses = %w[exited exited]
      stub_const("#{described_class}::REMOVAL_POLL_INTERVAL", 0)
      stop_running_on_stop

      manager.restart_app

      expect(runner.statuses).to be_empty
      expect(stops).to eq(["docker stop move-app-dev"])
      expect(runner.commands).to include("docker start move-app-dev")
    end

    it "removes a container that outlives the wait, and refuses to start if it is still there" do
      File.write(File.join(main, "config/master.key"), "k")
      runner.statuses = Array.new(described_class::REMOVAL_POLLS + 1, "exited")
      stub_const("#{described_class}::REMOVAL_POLL_INTERVAL", 0)
      stop_running_on_stop

      expect { manager.restart_app }.to raise_error(Thor::Error, /move-app-dev is still there after `docker stop`/)
      expect(runner.commands).to include("docker rm --force move-app-dev")
      expect(runner.commands).not_to include(a_string_matching(/docker (rename|start)/))
    end

    it "refuses an unreadable .env file before stopping the running container" do
      File.write(File.join(main, "config/master.key"), "k")
      env_file = File.join(main, ".env.development")
      File.write(env_file, "A=1")
      allow(File).to receive(:readable?).and_call_original
      allow(File).to receive(:readable?).with(env_file).and_return(false)

      expect { manager.restart_app }.to raise_error(Thor::Error, /not readable/)
      expect(stops).to be_empty
    end

    it "refuses a .env directory before stopping the running container" do
      File.write(File.join(main, "config/master.key"), "k")
      FileUtils.mkdir_p(File.join(main, ".env.development"))

      expect { manager.restart_app }.to raise_error(Thor::Error, /is a directory/)
      expect(stops).to be_empty
    end

    it "builds a missing image before stopping the running container" do
      File.write(File.join(main, "config/master.key"), "k")
      runner.image_present = false
      allow(runner).to receive(:run).and_wrap_original do |original, command, **opts|
        raise Thor::Error, "build failed" if Array(command).join(" ").start_with?("docker build")

        original.call(command, **opts)
      end

      expect { manager.restart_app }.to raise_error(Thor::Error, "build failed")
      expect(stops).to be_empty
    end
  end
end
