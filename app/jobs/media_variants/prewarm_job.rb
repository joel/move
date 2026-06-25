# frozen_string_literal: true

module MediaVariants
  # Restores the Apartment tenant (jobs never inherit the request's Current/tenant)
  # and pre-warms a captured photo's display variants off the request path (#316),
  # so the gallery/viewers are warm by the time anyone browses. Safe if the Media
  # was since deleted.
  class PrewarmJob < ApplicationJob
    queue_as :default

    def perform(media_id, tenant:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        media = Media.find_by(id: media_id)
        MediaVariants::Prewarm.call(media)
      end
    end
  end
end
