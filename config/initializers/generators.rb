Rails.application.config.generators do |generator|
  generator.javascripts true
  generator.stylesheets false # Tailwindcss lib/tailwindcss/engine.rb
  generator.orm :active_record, primary_key_type: :uuid
  generator.test_framework :rspec
  generator.fixture_replacement :factory_bot, dir: "spec/factories"
  generator.helper_specs true
  generator.controller_specs true
  generator.view_specs true
  generator.routing_specs true
  generator.request_specs true
  generator.system_specs true
end
