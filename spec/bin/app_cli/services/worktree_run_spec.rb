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

    it "says the dev database is shared with move-app-dev" do
      worktree_run.run(["true"])
      expect(shell).to have_received(:say).with("Database: move_development (shared with move-app-dev)")
    end

    %w[db:migrate db:migrate:redo db:rollback db:forward db:schema:load db:structure:load db:reset db:prepare
       db:setup db:drop db:drop:_unsafe db:purge db:truncate_all db:seed:replant db:fixtures:load].each do |task|
      it "refuses #{task} from a worktree without --yes, before any docker call" do
        expect { worktree_run.run(["bin/rails", task]) }
          .to raise_error(Thor::Error, /Refusing to run #{task} .* without --yes/)
        expect(shell).to have_received(:say).with(/Warning: #{task} changes the schema or data of move_development/)
        expect(runner.commands).to be_empty
        expect(db).not_to have_received(:start)
      end
    end

    [
      ["bash", "-c", "bin/rails db:migrate && echo ok"],
      ["sh", "-c", "cd /rails; bin/rails db:rollback"],
      %w[bundle exec rake db:rollback STEP=2],
      %w[env RAILS_ENV=development bin/rails db:drop],
      ["bash", "-c", "echo hi&&rails db:purge;"]
    ].each do |command|
      it "gates the task given to rails/rake in #{command.inspect}" do
        expect { worktree_run.run(command) }.to raise_error(Thor::Error, /without --yes/)
      end
    end

    [
      %w[echo db:migrate],
      %w[rg db:migrate doc],
      ["bash", "-c", "bin/rails runner 'puts 1' && echo db:migrate"],
      ["bash", "-c", "grep -r 'db:reset' lib"]
    ].each do |command|
      it "lets #{command.inspect} through: no rails/rake runs the task" do
        expect(worktree_run.run(command)).to eq(0)
        expect(shell).not_to have_received(:say).with(/Warning/)
      end
    end

    it "copes with unbalanced quotes" do
      expect { worktree_run.run(["bash", "-c", "bin/rails db:migrate 'oops"]) }
        .to raise_error(Thor::Error, /without --yes/)
    end

    it "runs a schema task with --yes, after the warning" do
      expect(worktree_run.run(%w[bin/rails db:migrate], confirmed: true)).to eq(0)
      expect(shell).to have_received(:say).with(/Warning: db:migrate changes/).ordered
      expect(runner.commands.last).to end_with("bin/rails db:migrate")
    end

    it "lets read-only db tasks through without --yes" do
      read_only = %w[db:migrate:status db:version db:test:prepare db:seed db:schema:dump db:prepared]
      read_only.each { |task| worktree_run.run(["bin/rails", task]) }
      expect(runner.commands.size).to eq(read_only.size)
      expect(shell).not_to have_received(:say).with(/Warning/)
    end

    it "does not ask for --yes on the main checkout" do
      main_checkout = AppCLI::Services::Checkout.new(path: worktree, branch: "main", main: true)
      run = described_class.new(shell: shell, env: "development", checkout: main_checkout, main_path: main,
                                runner: runner, db: db, tty: tty)
      expect(run.run(%w[bin/rails db:migrate])).to eq(0)
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

    it "prints the checkout banner and the shared database first" do
      worktree_run.interactive(:console)
      expect(shell).to have_received(:say).with("Running in #{worktree} (branch fix/x)").ordered
      expect(shell).to have_received(:say).with("Database: move_development (shared with move-app-dev)").ordered
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

    it "fails an all-filtered run of named specs when the image has no chromedriver" do
      worktree_run.test(["spec/system/gallery_lightbox_js_spec.rb"], system: true)

      file = described_class::FAIL_IF_NO_EXAMPLES_FILE
      expected = ["spec/system/gallery_lightbox_js_spec.rb", "--tag", "~js", "--require", file]
      script = Shellwords.shellsplit(runner.commands.last).last
      expect(script).to start_with("echo #{Shellwords.escape(described_class::FAIL_IF_NO_EXAMPLES_CODE)} > #{file} && ")
      expect(script).to end_with("rspec #{Shellwords.join(expected)}")
      expect(shell).to have_received(:say).with(/If every named spec is :js, the run fails with no examples/)
    end

    it "does not require fail_if_no_examples for the whole-suite run" do
      worktree_run.test([], system: true)
      expect(runner.commands.last).not_to include("fail-if-no-examples")
    end

    it "does not print the database banner for the test database" do
      worktree_run.test([], system: true)
      expect(shell).not_to have_received(:say).with(/Database:/)
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
