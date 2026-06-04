# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks

ENV["RAILS_ENV"] ||= "test"

Rake::Task[:default].prerequisites.clear if Rake::Task.task_defined?(:default)

begin
  require "rspec/core/rake_task"

  desc "Run all examples"
  RSpec::Core::RakeTask.new(:spec) do |t|
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
    sh "bundle exec rspec spec/system"
  end

  desc "Run ErbLint and RuboCop checks"
  task lint: :environment do
    sh "bin/erb_lint --lint-all"
    sh "bundle exec rubocop --lint --parallel --format simple"
  end

  desc "Autocorrect ErbLint and RuboCop lint issues"
  task "fix-lint" => :environment do
    sh "bin/erb_lint --lint-all -a"
    sh "bundle exec rubocop --lint --parallel -A --format simple"
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
