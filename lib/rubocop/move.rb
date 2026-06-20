# frozen_string_literal: true

# Loads this project's custom cops. Referenced from `.rubocop.yml` via
# `require: - ./lib/rubocop/move` so the pre-commit hook and CI both enforce them.
require_relative "cop/move/broad_rescue"
require_relative "cop/move/database_aggregation"
