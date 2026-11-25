require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/app-cmd/checkout_resolver"
require_relative "../../../../bin/cli-files/app-cmd/worktree_serve"

# Records docker commands instead of running them; containers are a name →
# { status:, mount: } map.
class FakeServeRunner
  attr_reader :commands
  attr_accessor :containers, :prepare_status, :answers_up, :router_running

  def initialize
    @commands = []
    @containers = {}
    @prepare_status = 0
    @answers_up = true
    @router_running = true
  end

  def run(command, quiet: false, allow_failure: false) # rubocop:disable Lint/UnusedMethodArgument
    line = Array(command).join(" ")
    @commands << line
    if line.start_with?("docker run --detach")
      name = line[/--name (\S+)/, 1]
      @containers[name] = { status: "running", mount: line[%r{--volume (\S+):/rails}, 1] }
    elsif line.start_with?("docker rm --force")
      @containers.delete(line.split.last)
    end
    line # truthy, like a successful Kernel.system
  end

  def run_status(command)
    @commands << Array(command).join(" ")
    prepare_status
  end

  def capture(command, **)
    @commands << command
    case command
    when /RUBY_VERSION/ then AppCLI::Services::EnvConfig.new("development").ruby_version
    when /docker ps/ then names_listed(all: command.include?("--all"))
    when /docker inspect --format/ then containers.dig(command.split.last, :mount).to_s
    when /curl/ then answers_up ? "200" : "000"
    else ""
    end
  end

  # `docker ps` lists running containers; `--all` adds stopped ones.
  def names_listed(all:)
    containers.select { |_, c| all || c[:status] == "running" }.keys.join("\n")
  end

  def image_exists?(_image) = true
  def ensure_network(_name) = nil

  def container_status(name)
    return (router_running ? "running" : "missing") if name == "move-router"

    containers.dig(name, :status) || "missing"
  end

  def container_running?(name) = container_status(name) == "running"
end

RSpec.describe AppCLI::Services::WorktreeServe do
  subject(:serve) do
    described_class.new(shell: shell, checkout: checkout, main_path: main, app: app,
                        runner: runner, db: db, route: route)
  end

  let(:tmp) { Dir.mktmpdir("wtserve") }
  let(:shell) { instance_double(Thor::Shell::Basic, say: nil) }
  let(:runner) { FakeServeRunner.new }
  let(:db) { instance_double(AppCLI::Services::DbService, start: nil) }
  let(:route) { instance_double(AppCLI::Services::WorktreeRoute, write!: nil, remove!: nil) }

  def app = AppCLI::Services::WorktreeApp.new("w1")
  def checkout = AppCLI::Services::Checkout.new(path: worktree, branch: "feature/x", main: false)
  def main = File.join(tmp, "main")
  def worktree = File.join(tmp, "wt")
  def docker_runs = runner.commands.grep(/\Adocker run/).reject { |c| c.include?("RUBY_VERSION") || c.include?("bundle check") }

  before do
    FileUtils.mkdir_p([File.join(main, "config"), worktree])
    File.write(File.join(main, "config/master.key"), "k")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("MOVE_APP_READY_TIMEOUT", "").and_return("1")
  end

  after { FileUtils.remove_entry(tmp) }

  describe "#serve" do
    it "prepares its own database in a throwaway container first" do
      serve.serve

      expect(db).to have_received(:start)
      expect(docker_runs.first).to start_with("docker run --rm --env SKIP_TEST_DATABASE=true")
      expect(docker_runs.first).to include("--env MOVE_DEV_DATABASE=move_development_wt_w1",
                                           "--env MOVE_TENANT_ZONE=w1.wt.move-easy.docker",
                                           "--env WEBAUTHN_RP_ID=w1.wt.move-easy.docker",
                                           "--volume #{worktree}:/rails", "db:prepare", "tailwindcss:build")
    end

    it "then starts the container, waits for /up, and adds the route" do
      serve.serve

      server = docker_runs.last
      expect(server).to start_with("docker run --detach --name move-app-wt-w1")
      expect(server).to include("--env MOVE_DEV_DATABASE=move_development_wt_w1", "-P /tmp/server.pid")
      expect(server).not_to include("--publish")
      expect(route).to have_received(:write!)
      expect(shell).to have_received(:say).with("Serving #{worktree} at https://move.w1.wt.move-easy.docker")
      expect(shell).to have_received(:say).with(%r{Stop it with `bin/cli app stop --name w1`})
    end

    it "never names main's database or container" do
      serve.serve
      expect(runner.commands.join("\n")).not_to match(/move_development(?!_wt_)|--name move-app-dev/)
    end

    it "refuses the main checkout before any docker call" do
      main_checkout = AppCLI::Services::Checkout.new(path: main, branch: "main", main: true)
      expect do
        described_class.new(shell: shell, checkout: main_checkout, main_path: main, app: app,
                            runner: runner, db: db, route: route).serve
      end.to raise_error(Thor::Error, /is the main checkout/)
      expect(runner.commands).to be_empty
    end

    it "refuses an app whose database would be main's" do
      shared = instance_double(AppCLI::Services::WorktreeApp, database: "move_development", container: "move-app-wt-x")
      expect do
        described_class.new(shell: shell, checkout: checkout, main_path: main, app: shared,
                            runner: runner, db: db, route: route).serve
      end.to raise_error(Thor::Error, /would share a database/)
      expect(runner.commands).to be_empty
    end

    it "stops before starting anything when preparing the database fails" do
      runner.prepare_status = 1
      expect { serve.serve }.to raise_error(Thor::Error, /Preparing move_development_wt_w1 failed/)
      expect(docker_runs.grep(/--detach/)).to be_empty
      expect(route).not_to have_received(:write!)
    end

    it "removes a container that does not answer /up, with its logs, and adds no route" do
      runner.answers_up = false
      expect { serve.serve }.to raise_error(Thor::Error, %r{did not answer /up.*move-app-dev was not touched}m)
      expect(runner.commands).to include("docker rm --force move-app-wt-w1")
      expect(route).not_to have_received(:write!)
    end

    it "refuses a fourth worktree app and lists the running ones" do
      %w[a b c].each { |l| runner.containers["move-app-wt-#{l}"] = { status: "running", mount: "/#{l}" } }
      expect { serve.serve }.to raise_error(Thor::Error, /3 worktree apps already run \(move-app-wt-a, .*cap is 3/)
      expect(db).not_to have_received(:start)
    end

    it "does not count stopped leftovers toward the cap" do
      %w[a b c].each { |l| runner.containers["move-app-wt-#{l}"] = { status: "exited", mount: "/#{l}" } }
      serve.serve
      expect(docker_runs.last).to start_with("docker run --detach --name move-app-wt-w1")
    end

    it "refuses when move-router is down even if this checkout is already served" do
      runner.containers["move-app-wt-w1"] = { status: "running", mount: worktree }
      runner.router_running = false
      expect { serve.serve }.to raise_error(Thor::Error, %r{bin/cli router start})
      expect(route).not_to have_received(:write!)
    end

    it "refuses a name another checkout's app already uses (it would share the database)" do
      runner.containers["move-app-wt-w1"] = { status: "running", mount: "/elsewhere" }
      expect { serve.serve }.to raise_error(Thor::Error, %r{serves /elsewhere.*--name W}m)
      expect(docker_runs).to be_empty
    end

    it "only re-adds the route when this checkout is already served" do
      runner.containers["move-app-wt-w1"] = { status: "running", mount: worktree }
      serve.serve
      expect(docker_runs).to be_empty
      expect(route).to have_received(:write!)
    end

    it "refuses when move-router is down" do
      runner.router_running = false
      expect { serve.serve }.to raise_error(Thor::Error, %r{bin/cli router start})
      expect(db).not_to have_received(:start)
    end

    it "refuses while another serve holds the lock" do
      AppCLI::Services::TestLock.new(path: File.join(main, described_class::LOCK_FILE)).synchronize("other") do
        expect { serve.serve }.to raise_error(Thor::Error, %r{another `bin/cli app serve`})
      end
    end
  end

  describe "#stop" do
    before { runner.containers["move-app-wt-w1"] = { status: "running", mount: worktree } }

    it "removes the container and the route, keeping the database" do
      serve.stop
      expect(runner.commands).to include("docker rm --force move-app-wt-w1")
      expect(route).to have_received(:remove!)
      expect(runner.commands.grep(/dropdb/)).to be_empty
    end

    it "drops the worktree database only when asked" do
      serve.stop(drop_db: true)
      expect(runner.commands)
        .to include("docker exec move-db-dev dropdb --username postgres --if-exists move_development_wt_w1")
    end

    it "refuses to stop the app another checkout serves" do
      runner.containers["move-app-wt-w1"][:mount] = "/elsewhere"
      expect { serve.stop }.to raise_error(Thor::Error, %r{serves /elsewhere})
      expect(route).not_to have_received(:remove!)
    end

    it "stops by name alone when there is no checkout" do
      by_name = described_class.new(shell: shell, checkout: nil, main_path: main, app: app,
                                    runner: runner, db: db, route: route)
      runner.containers["move-app-wt-w1"][:mount] = "/deleted"
      by_name.stop
      expect(runner.commands).to include("docker rm --force move-app-wt-w1")
    end
  end
end
