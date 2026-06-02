# frozen_string_literal: true

module BuildTasks
  def self.assets_precompile?
    defined?(Rake) &&
      Rake.respond_to?(:application) &&
      Rake.application.top_level_tasks.any? { |task| task.start_with?("assets:") }
  end
end
