require "spec_helper"
require_relative "../../../../bin/cli-files/services/app-cmd/app_commands"

RSpec.describe AppCLI::Services::AppCommands do
  let(:checkout) { AppCLI::Services::Checkout.new(path: "/wt", branch: "fix/x", main: false) }
  let(:resolver) { instance_double(AppCLI::Services::CheckoutResolver, resolve: checkout, main_checkout: main_checkout) }
  let(:worktree_run) { instance_double(AppCLI::Services::WorktreeRun, interactive: 0, test: 0) }
  let(:app_service) { instance_double(AppCLI::Services::AppService, console: nil, connect: nil) }

  before do
    allow(AppCLI::Services::CheckoutResolver).to receive(:new).and_return(resolver)
    allow(AppCLI::Services::WorktreeRun).to receive(:new).and_return(worktree_run)
    allow(AppCLI::Services::AppService).to receive(:new).and_return(app_service)
  end

  def main_checkout = AppCLI::Services::Checkout.new(path: "/main", branch: "main", main: true)
  def commands(options = {}) = described_class.new([], options)

  def exit_status
    yield
    nil
  rescue SystemExit => e
    e.status
  end

  %i[console connect].each do |kind|
    describe "##{kind}" do
      it "attaches to the long-lived app container without --repo" do
        commands.public_send(kind)

        expect(app_service).to have_received(kind)
        expect(AppCLI::Services::WorktreeRun).not_to have_received(:new)
      end

      it "passes the environment through without --repo" do
        commands.public_send(kind, "prod")
        expect(AppCLI::Services::AppService).to have_received(:new).with(hash_including(env: "production"))
      end

      it "runs a throwaway session for the --repo checkout and exits with its status" do
        allow(worktree_run).to receive(:interactive).and_return(7)

        expect(exit_status { commands("repo" => "fix/x").public_send(kind) }).to eq(7)
        expect(resolver).to have_received(:resolve).with("fix/x")
        expect(AppCLI::Services::WorktreeRun).to have_received(:new)
          .with(hash_including(env: "development", checkout: checkout, main_path: "/main"))
        expect(worktree_run).to have_received(:interactive).with(kind)
        expect(app_service).not_to have_received(kind)
      end

      it "refuses prod with --repo, with the app run message" do
        allow(AppCLI::Services::WorktreeRun).to receive(:new).and_call_original

        expect { commands("repo" => "fix/x").public_send(kind, "prod") }
          .to raise_error(Thor::Error, /only supports the dev environment/)
        expect(app_service).not_to have_received(kind)
      end
    end
  end

  describe "#run_command" do
    before { allow(worktree_run).to receive(:run).and_return(0) }

    it "passes --yes through as confirmation" do
      exit_status { commands("repo" => "fix/x", "yes" => true).run_command("bin/rails", "db:migrate") }
      expect(worktree_run).to have_received(:run).with(%w[bin/rails db:migrate], confirmed: true)
    end

    it "is unconfirmed by default" do
      exit_status { commands("repo" => "fix/x", "yes" => false).run_command("true") }
      expect(worktree_run).to have_received(:run).with(["true"], confirmed: false)
    end
  end

  describe "#serve" do
    let(:serve) { instance_double(AppCLI::Services::WorktreeServe, serve: nil, stop: nil) }

    before { allow(AppCLI::Services::WorktreeServe).to receive(:new).and_return(serve) }

    it "serves the --repo worktree under its directory name" do
      commands("repo" => "fix/x").serve

      expect(resolver).to have_received(:resolve).with("fix/x")
      expect(AppCLI::Services::WorktreeServe).to have_received(:new) do |args|
        expect(args).to include(checkout: checkout, main_path: "/main")
        expect(args[:app].label).to eq("wt")
      end
      expect(serve).to have_received(:serve)
    end

    it "uses --name for the app, zone and database" do
      commands("repo" => "fix/x", "name" => "demo-1").serve
      expect(AppCLI::Services::WorktreeServe).to have_received(:new) { |args| expect(args[:app].label).to eq("demo-1") }
    end

    it "refuses a --name that is not a label" do
      expect { commands("repo" => "fix/x", "name" => "Bad.Name").serve }.to raise_error(Thor::Error, /not a usable/)
    end
  end

  describe "#stop" do
    let(:serve) { instance_double(AppCLI::Services::WorktreeServe, stop: nil) }

    before do
      allow(AppCLI::Services::WorktreeServe).to receive(:new).and_return(serve)
      allow(app_service).to receive(:stop)
    end

    it "stops move-app-dev without --repo or --name" do
      commands.stop
      expect(app_service).to have_received(:stop)
      expect(AppCLI::Services::WorktreeServe).not_to have_received(:new)
    end

    it "stops the served worktree app for --repo, keeping its database by default" do
      commands("repo" => "fix/x", "drop_db" => false).stop
      expect(serve).to have_received(:stop).with(drop_db: false)
      expect(app_service).not_to have_received(:stop)
    end

    it "stops by --name without resolving a checkout, and passes --drop-db" do
      commands("name" => "gone", "drop_db" => true).stop

      expect(resolver).not_to have_received(:resolve)
      expect(AppCLI::Services::WorktreeServe).to have_received(:new).with(hash_including(checkout: nil))
      expect(serve).to have_received(:stop).with(drop_db: true)
    end

    it "refuses prod with --repo" do
      expect { commands("repo" => "fix/x").stop("prod") }.to raise_error(Thor::Error, /only supports the dev/)
      expect(serve).not_to have_received(:stop)
    end
  end

  describe "#test_command" do
    it "runs the unit suite by default" do
      expect(exit_status { commands("system" => false).test_command }).to eq(0)
      expect(worktree_run).to have_received(:test).with([], system: false)
    end

    it "passes --system and the rspec arguments through" do
      allow(worktree_run).to receive(:test).and_return(1)

      status = exit_status { commands("repo" => "fix/x", "system" => true).test_command("spec/system/a_spec.rb") }
      expect(status).to eq(1)
      expect(worktree_run).to have_received(:test).with(["spec/system/a_spec.rb"], system: true)
    end
  end
end
