require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/app-cmd/checkout_resolver"
require_relative "../../../../bin/cli-files/app-cmd/worktree_run"

# Records docker commands instead of running them.
class FakeWorktreeRunner
  attr_reader :commands
  attr_accessor :status, :image_sum, :test_container_status

  def initialize(image_sum:)
    @commands = []
    @status = 0
    @image_sum = image_sum
    @test_container_status = "missing"
  end

  def run_status(command)
    @commands << command.join(" ")
    status
  end

  def image_exists?(_image) = true
  def ensure_network(_name) = nil
  def capture(*, **) = image_sum
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
