return unless Gem.loaded_specs.key?("rubocop")

require "rubocop/rake_task"

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["-A"] # auto_correct
end
