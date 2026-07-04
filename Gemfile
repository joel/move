source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "4.0.5"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"

# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"

# Use postgresql as the database for Active Record
gem "pg"
# pgvector <-> Active Record mapping for D8 hybrid search (array<->vector, ANN).
gem "neighbor"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# https://tailwindcss.com/blog/standalone-cli # TL;DR no Node.js or npm required.
gem "tailwindcss-ruby"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"
# image_processing 2.0 no longer bundles an image backend; declare libvips (Rails'
# default variant_processor) explicitly. Requires libvips at runtime when variants
# are actually processed. require: false — image_processing loads it on demand.
gem "ruby-vips", require: false

# S3-compatible Active Storage backend (SeaweedFS in dev/prod). require: false —
# Active Storage loads it on demand for the S3 service.
gem "aws-sdk-s3", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "ffaker"

  gem "bullet" # Use https://github.com/charkost/prosopite instead
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  gem "overcommit", require: false

  gem "bundle-audit", require: false
  gem "erb_lint", require: false
  gem "rubocop", require: false
  gem "rubocop-capybara", require: false
  gem "rubocop-factory_bot", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rake", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false

  # Modular boundary analysis (domain dependencies + privacy). `packwerk` is the
  # static analyzer; `packwerk-extensions` adds the `enforce_architecture` (layer
  # tiers) and `enforce_visibility` checkers on top of core dependencies/privacy.
  # Loaded only by the `packwerk` CLI / CI step, never by the app runtime.
  gem "packwerk", require: false
  gem "packwerk-extensions", require: false

  # Static type checking — RBS signatures (inline `#:`/`@rbs` comments) checked by
  # Steep. Scope: the actions layer + models (see Steepfile +
  # doc/project/type-checking.md). Loaded only by the `steep`/`rbs`/`rbs_rails`
  # CLIs / CI steps, never by the app runtime. rbs_rails generates the
  # schema-derived model signatures (sig/rbs_rails/, freshness-checked in CI).
  gem "rbs", "~> 4.0", require: false
  gem "rbs_rails", "~> 0.13", require: false
  gem "steep", "~> 2.0", require: false

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"

  # For performance profiling
  gem "rack-mini-profiler", require: false

  # For memory profiling
  gem "memory_profiler"

  # For call-stack profiling flamegraphs
  gem "stackprof"

  # For CPU profiling flamegraphs
  gem "flamegraph"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  # Extract text/content streams from generated PDFs so specs can assert what
  # actually prints (not just that rendering doesn't raise) — #508.
  gem "pdf-reader", require: false
  gem "rspec-rails"
  gem "selenium-webdriver"
end

gem "phlex-rails", "~> 2.0"

gem "foreman", "~> 0.90.0"

# ── Authentication (Rodauth: passkeys, email links, Google) ──
gem "omniauth-google-oauth2"
gem "rodauth-omniauth"
gem "rodauth-rails"
gem "sequel-activerecord_connection", require: false
gem "tilt", require: false
gem "webauthn"

# Authorization
gem "action_policy"

# Business logic lives in app/actions (not models), composed with Dry::Monads
# result/do notation. See app/actions/AGENTS.md.
gem "dry-monads", "~> 1.10"

# Multi-tenancy via PostgreSQL schema-per-tenant (do not hand-roll tenancy).
# https://github.com/rails-on-services/apartment
gem "ros-apartment", "~> 3.4", require: "apartment"

# Soft delete for user-authored domain records (Technical Foundation §9, Domain
# §11). Deletes set discarded_at instead of destroying; cascade restore is
# expressed explicitly via Discards::Cascade(Restore) + a discard_batch_id trace
# (callbacks alone cannot express the restore graph). https://github.com/jhawthorn/discard
gem "discard", "~> 2.0"

# Field-level versioning for user-authored records (Technical Foundation §6/§7;
# replaces paper_trail). Postgres-trigger based (log_data jsonb per row); actions
# attribute edits via Logidze.with_responsible. Powers the activity feed's revert.
# https://github.com/palkan/logidze
gem "logidze", "~> 1.4"

# D13 — MCP assistant surface. Official Model Context Protocol SDK; the MCP
# server + tool definitions are wired into a Rails controller via the stateless
# StreamableHTTP transport (per-Move integration tokens, shared domain actions).
gem "mcp"

# D9 — Labels, QR & Scan. Pure-Ruby PDF generation for the A7 exterior label and
# A4 manifest (no system binary, so deploys stay infra-free). QR codes are
# rendered to PNG via rqrcode (+ chunky_png) and embedded in the PDFs.
gem "chunky_png", "~> 1.4"
gem "prawn", "~> 2.5"
gem "prawn-table", "~> 0.2"
gem "rqrcode", "~> 3.0"

# Error monitoring — Sentry (#528). Enabled only when SENTRY_DSN is present
# (production via Doppler move/prd); the SDK no-ops without a DSN, so dev/test
# stay silent. sentry-rails auto-instruments controllers + ActiveJob/Solid Queue.
gem "sentry-rails"
gem "sentry-ruby"

# Modular boundaries — Packwerk. `packs-rails` is a RUNTIME dependency (not
# dev-only): it adds `packs/**/app/**` to the autoload + eager_load paths, so the
# domain code physically living under `packs/` is loaded in every environment
# (including production). The Packwerk analyzer + its enforcement extensions are
# dev-only (see the :development group). See doc/project/packwerk-boundaries.md.
gem "packs-rails"

group :test do
  gem "phlex-testing-capybara", require: false
end
