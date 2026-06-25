# frozen_string_literal: true

# Reaps spent apex->subdomain handoff tokens (#280) so the public-schema table
# does not grow unbounded — every login mints one row with a 60-second TTL.
# Scheduled daily (config/recurring.yml). SessionHandoffToken is an excluded
# Apartment model (public only), so this runs once, not per tenant.
#
# `delete_all` is correct here: the rows carry no attachments or callbacks, and
# a spent token (expired or consumed) is never read again.
class PurgeStaleSessionHandoffTokensJob < ApplicationJob
  def perform
    SessionHandoffToken.purgeable.delete_all
  end
end
