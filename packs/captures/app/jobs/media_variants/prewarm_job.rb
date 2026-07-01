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
        return Rails.logger.warn("[media_variants:prewarm_job] media #{media_id} not found") unless media

        warmed_count = MediaVariants::Prewarm.call(media)
        Rails.logger.info("[media_variants:prewarm_job] warmed #{warmed_count}/2 variants for media #{media_id}")
      end
    end
  end
end
