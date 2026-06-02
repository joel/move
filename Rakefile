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

desc "Run all checks"
task default: %w[spec rubocop erb_lint] do
  Thor::Base.shell.new.say_status :OK, "All checks passed!"
end

desc "Apply auto-corrections"
task fix: %w[rubocop:autocorrect_all erb_lint:autocorrect] do
  Thor::Base.shell.new.say_status :OK, "All fixes applied!"
end
