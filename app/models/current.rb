# frozen_string_literal: true

# Per-request context. `organization` / `organization_membership` are resolved
# from the subdomain in ApplicationController. Move-scoped attributes
# (`move` / `move_membership`) are populated in a later phase.
class Current < ActiveSupport::CurrentAttributes
  attribute :organization, :organization_membership
end
