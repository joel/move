# frozen_string_literal: true

# Thread/fiber-local context, restored explicitly inside background jobs (never
# carried across the enqueue boundary — TF). Holds the active Apartment tenant.
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant
end
