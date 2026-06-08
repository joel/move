# frozen_string_literal: true

# Thread/fiber-local context, restored explicitly inside background jobs (never
# carried across the enqueue boundary — TF). Holds the active Apartment tenant
# and, for in-request rendering, the active Move + nav section so the shared app
# shell can build Move-scoped nav links and highlight the current destination.
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant
  attribute :move
  attribute :nav_section
end
