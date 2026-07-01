require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MoveApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # ros-apartment switches the tenant by SET search_path on
    # ActiveRecord::Base.connection (the subdomain elevator). Rails 8.1's default
    # *temporary* connection checkout means a later per-query lease (e.g. Active
    # Storage's proxy controller, or a write) can grab a different pool connection
    # that Apartment defaults to the `public` schema — so tenant rows 404 / writes
    # miss the tenant. Pin the connection per thread so the elevator's search_path
    # persists across the whole request. (Until ros-apartment supports 8.1's
    # connection model natively.)
    config.active_record.permanent_connection_checkout = true

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `rubocop` holds custom cops (lib/rubocop/cop/move) loaded only by RuboCop's
    # own runner via `.rubocop.yml`; they subclass `RuboCop::Cop::Base`, which the
    # Rails app runtime never requires — so eager-loading them (CI sets
    # `eager_load = true`) would raise. Keep them out of the app autoloaders.
    config.autoload_lib(ignore: %w[assets tasks templates rubocop middleware])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    # config.generators.system_tests = nil

    logger           = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.log_tags  = [:request_id]
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
    config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug").to_sym

    # :sql is required for Apartment schema-per-tenant: structure.sql captures
    # the public schema, extensions and search_path that :ruby schema.rb cannot.
    config.active_record.schema_format = :sql

    # Human-facing brand name. Decoupled from the Ruby module (MoveApp) so the
    # product is always shown as "Move".
    config.x.brand_name = "Move"

    config.hosts.clear if ENV["RAILS_ALLOW_ALL_HOSTS"].present?
  end
end
