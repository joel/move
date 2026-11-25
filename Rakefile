# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks

ENV["RAILS_ENV"] ||= "test"

Rake::Task[:default].prerequisites.clear if Rake::Task.task_defined?(:default)

begin
  require "rspec/core/rake_task"

  # Reason: rspec-rails already defines `spec` (with a `spec/**` pattern that
  # misses packs/*/spec); a second RakeTask would only ADD an action, so `rake
  # spec` ran the suite twice. Drop its action, keep its `spec:prepare` prereq.
  Rake::Task[:spec].clear_actions if Rake::Task.task_defined?(:spec)

  desc "Run all examples"
  RSpec::Core::RakeTask.new(:spec) do |t|
    # Reason: RSpec's own default pattern, which RSpec resolves under each run path:
    # `spec/` plus the packs/*/spec dirs packs-rails adds (#439). It never globs the
    # repo root (lib/templates is untouched). The RakeTask default `spec/**…` would
    # become packs/<pack>/spec/spec/** for a pack and match nothing.
    t.pattern = "**{,/*/**}/*_spec.rb"
    t.ruby_opts = [
      "-w", # turn warnings on for your script
      "--yjit" # enable in-process JIT compiler
    ]
  end
rescue LoadError
  puts "RSpec is not part of the bundle. Skipping RSpec tasks."
end

require "thor"

namespace :project do
  desc "Run non-system specs"
  task tests: :environment do
    sh %(bundle exec rspec spec --exclude-pattern "spec/system/**/*_spec.rb")
  end

  desc "Run system specs"
  task "system-tests" => :environment do
    # Reason: CI runs system specs with the rack_test driver (browser-independent);
    # mirror it so `rake` matches CI instead of defaulting to selenium_chrome.
    sh({ "TEST_BROWSER" => "rack_test" }, "bundle exec rspec spec/system")
  end

  desc "Run ErbLint and RuboCop checks"
  task lint: :environment do
    sh "bin/erb_lint --lint-all"
    # Reason: CI runs the full RuboCop suite, not just lint cops.
    sh "bundle exec rubocop --parallel --format simple"
  end

  desc "Autocorrect ErbLint and RuboCop issues"
  task "fix-lint" => :environment do
    sh "bin/erb_lint --lint-all -a"
    # Reason: autocorrect the same full suite that `lint` checks.
    sh "bundle exec rubocop --parallel -A --format simple"
  end
end

desc "Run all checks"
task default: %w[project:tests project:system-tests project:lint] do
  Thor::Base.shell.new.say_status :OK, "All checks passed!"
end

desc "Apply auto-corrections"
task fix: %w[project:fix-lint] do
  Thor::Base.shell.new.say_status :OK, "All fixes applied!"
end
