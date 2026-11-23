require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/app-cmd/checkout_resolver"
require_relative "../../../../bin/cli-files/app-cmd/worktree_run"

# Records docker commands instead of running them.
class FakeWorktreeRunner
  attr_reader :commands
  attr_accessor :status, :image_sum, :test_container_status, :chromedriver

  def initialize(image_sum:)
    @commands = []
    @status = 0
    @image_sum = image_sum
    @test_container_status = "missing"
    @chromedriver = nil
  end

  def run_status(command)
    @commands << command.join(" ")
    status
  end

  def image_exists?(_image) = true
  def ensure_network(_name) = nil
  def capture(command, **) = command.include?("chromedriver") ? chromedriver : image_sum
  def container_status(_name) = test_container_status
end

RSpec.describe AppCLI::Services::WorktreeRun do
  subject(:worktree_run) do
    checkout = AppCLI::Services::Checkout.new(path: worktree, branch: "fix/x", main: false)
    described_class.new(shell: shell, env: "development", checkout: checkout, main_path: main,
                        runner: runner, db: db, tty: tty)
  end

  let(:tmp) { Dir.mktmpdir("wtrun") }
  let(:shell) { instance_double(Thor::Shell::Basic, say: nil) }
  let(:runner) { FakeWorktreeRunner.new(image_sum: "#{Digest::SHA256.hexdigest("lock")}  /rails/Gemfile.lock") }
  let(:db) { instance_double(AppCLI::Services::DbService, start: nil) }
  let(:tty) { { stdin: false, stdout: false } }

  def main = File.join(tmp, "main")
  def worktree = File.join(tmp, "wt")

  before do
    FileUtils.mkdir_p([File.join(main, "config"), worktree])
    File.write(File.join(main, "config/master.key"), "k")
    File.write(File.join(worktree, "Gemfile.lock"), "lock")
  end

  after { FileUtils.remove_entry(tmp) }

  it "refuses the production environment before any docker call" do
    checkout = AppCLI::Services::Checkout.new(path: worktree, branch: "fix/x", main: false)
    expect do
      described_class.new(shell: shell, env: "production", checkout: checkout, main_path: main,
                          runner: runner, db: db, tty: tty)
    end.to raise_error(Thor::Error, /only supports the dev environment/)
    expect(runner.commands).to be_empty
  end

  describe "#run" do
    it "announces the checkout first, brings up db and mounts the worktree" do
      expect(worktree_run.run(["bin/rails", "runner", "puts 1"])).to eq(0)

      expect(shell).to have_received(:say).with("Running in #{worktree} (branch fix/x)").ordered
      expect(db).to have_received(:start)
      command = runner.commands.last
      expect(command).to include("--volume #{worktree}:/rails", "--env RAILS_ENV=development",
                                 "RAILS_MASTER_KEY=$(cat #{main}/config/master.key)")
      expect(command).to end_with("workeverywhere/move-app:latest bin/rails runner puts\\ 1")
      expect(command).not_to include("--name", "--interactive")
    end

    it "returns the command's exit status" do
      runner.status = 3
      expect(worktree_run.run(["false"])).to eq(3)
    end

    it "refuses an empty command" do
      expect { worktree_run.run([]) }.to raise_error(Thor::Error, /No command given/)
    end

    context "with stdin on a TTY" do
      let(:tty) { { stdin: true, stdout: false } }

      it "attaches stdin without allocating a tty when stdout is piped" do
        worktree_run.run(["bash"])
        expect(runner.commands.last).to include("--interactive")
        expect(runner.commands.last).not_to include("--tty")
      end
    end

    context "with both ends on a TTY" do
      let(:tty) { { stdin: true, stdout: true } }

      it "allocates a tty" do
        worktree_run.run(["bash"])
        expect(runner.commands.last).to include("--interactive --tty")
      end
    end

    it "writes nothing into the worktree beyond its tmp and log dirs" do
      worktree_run.run(["true"])
      expect(Dir.children(worktree).sort).to eq(%w[Gemfile.lock log tmp])
    end

    it "warns when the worktree's Gemfile.lock differs from the image's" do
      runner.image_sum = "deadbeef  /rails/Gemfile.lock"
      worktree_run.run(["true"])
      expect(shell).to have_received(:say).with(/Gemfile.lock differs from the one in workeverywhere/)
    end

    it "does not warn when the lockfiles match" do
      worktree_run.run(["true"])
      expect(shell).not_to have_received(:say).with(/differs/)
    end
  end

  describe "#interactive" do
    it "opens a Rails console in a throwaway container for the checkout" do
      expect(worktree_run.interactive(:console)).to eq(0)

      expect(db).to have_received(:start)
      command = runner.commands.last
      expect(command).to start_with("docker run --rm")
      expect(command).to include("--volume #{worktree}:/rails", "--network network.docker-shared-services")
      expect(command).to end_with("workeverywhere/move-app:latest bin/rails console")
      expect(command).not_to include("--name", "docker exec")
    end

    it "prints the checkout banner first" do
      worktree_run.interactive(:console)
      expect(shell).to have_received(:say).with("Running in #{worktree} (branch fix/x)")
    end

    it "opens a shell for :connect and returns its exit status" do
      runner.status = 130
      expect(worktree_run.interactive(:connect)).to eq(130)
      expect(runner.commands.last).to end_with("workeverywhere/move-app:latest bash")
    end

    context "with a terminal" do
      let(:tty) { { stdin: true, stdout: true } }

      it "attaches a tty" do
        worktree_run.interactive(:console)
        expect(runner.commands.last).to include("--interactive --tty")
      end
    end

    it "keeps stdin open for a piped script but allocates no tty without a terminal" do
      worktree_run.interactive(:connect)
      expect(runner.commands.last).to include("--interactive")
      expect(runner.commands.last).not_to include("--tty")
    end

    it "rejects an unknown session kind" do
      expect { worktree_run.interactive(:irb) }.to raise_error(KeyError)
      expect(runner.commands).to be_empty
    end
  end

  describe "#test with system: true" do
    it "runs spec/system under rack_test in the test container" do
      runner.chromedriver = "/usr/bin/chromedriver\n"
      expect(worktree_run.test([], system: true)).to eq(0)

      command = runner.commands.last
      expect(command).to include("--name move-app-test", "--env RAILS_ENV=test", "--env TEST_BROWSER=rack_test")
      expect(command).to end_with("bundle\\ exec\\ rspec\\ spec/system")
      expect(shell).not_to have_received(:say).with(/chromedriver/)
    end

    it "skips :js specs and says so when the image has no chromedriver" do
      worktree_run.test([], system: true)

      expect(runner.commands.last).to end_with(Shellwords.escape("rspec #{Shellwords.join(%w[spec/system --tag ~js])}"))
      expect(shell).to have_received(:say)
        .with("chromedriver is not in workeverywhere/move-app:latest: skipping :js system specs " \
              "(--tag ~js); they run in CI only.").once
    end

    it "keeps the caller's system spec paths" do
      runner.chromedriver = "/usr/bin/chromedriver\n"
      worktree_run.test(["spec/system/boxes_spec.rb:12"], system: true)
      expect(runner.commands.last).to end_with("rspec\\ spec/system/boxes_spec.rb:12")
    end

    it "keeps a dot-relative system spec path" do
      runner.chromedriver = "/usr/bin/chromedriver\n"
      worktree_run.test(["./spec/system/boxes_spec.rb"], system: true)
      expect(runner.commands.last).to end_with("rspec\\ ./spec/system/boxes_spec.rb")
    end

    it "does not mistake a lookalike directory for spec/system" do
      runner.chromedriver = "/usr/bin/chromedriver\n"
      worktree_run.test(["spec/systematic_spec.rb"], system: true)
      expect(runner.commands.last).to end_with("rspec\\ spec/system\\ spec/systematic_spec.rb")
    end

    it "prefixes spec/system when only options are given" do
      runner.chromedriver = "/usr/bin/chromedriver\n"
      worktree_run.test(["--format", "doc"], system: true)
      expect(runner.commands.last).to end_with("rspec\\ spec/system\\ --format\\ doc")
    end

    it "takes the same lock as the unit run" do
      lock = AppCLI::Services::TestLock.new(path: File.join(main, described_class::LOCK_FILE))
      lock.synchronize("/other (branch o)") do
        expect { worktree_run.test([], system: true) }.to raise_error(Thor::Error, /is running/)
      end
      expect(runner.commands).to be_empty
    end

    it "does not set TEST_BROWSER for the unit run" do
      worktree_run.test([])
      expect(runner.commands.last).not_to include("TEST_BROWSER")
    end
  end

  describe "#test" do
    it "runs the unit suite in the fixed test container under RAILS_ENV=test" do
      expect(worktree_run.test([])).to eq(0)

      command = runner.commands.last
      expect(command).to include("--name move-app-test", "--env RAILS_ENV=test", "--volume #{worktree}:/rails")
      expect(command).to include("bin/rails\\ db:test:prepare\\ \\&\\&\\ bundle\\ exec\\ rspec\\ spec\\ --exclude-pattern")
    end

    it "passes rspec arguments through and returns rspec's status" do
      runner.status = 1
      expect(worktree_run.test(["spec/actions/foo_spec.rb", "--format", "doc"])).to eq(1)
      expect(runner.commands.last).to include("rspec\\ spec/actions/foo_spec.rb\\ --format\\ doc")
    end

    it "refuses to start while another run holds the lock" do
      lock = AppCLI::Services::TestLock.new(path: File.join(main, described_class::LOCK_FILE))
      lock.synchronize("/other (branch o)") do
        expect { worktree_run.test([]) }.to raise_error(Thor::Error, %r{is running \(pid \d+, /other})
      end
      expect(runner.commands).to be_empty
    end

    it "refuses a leftover test container with a removal hint" do
      runner.test_container_status = "exited"
      expect { worktree_run.test([]) }.to raise_error(Thor::Error, /docker rm -f move-app-test/)
      expect(runner.commands).to be_empty
    end
  end
end
