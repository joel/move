# frozen_string_literal: true

module Items
  # Runs item-image generation off the request path (it calls a slow vendor image
  # API). Restores the Apartment tenant (jobs never inherit it), then delegates to
  # Items::GenerateImage, which owns both the success and failure domain events
  # (the broadcast subscriber turns them into the live card swap).
  class GenerateImageJob < ApplicationJob
    queue_as :default

    def perform(item_id, tenant:, actor_id: nil)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        item = Item.find_by(id: item_id)
        next if item.nil? || item.source_media_id.present?

        actor = actor_id && User.find_by(id: actor_id)
        Items::GenerateImage.new.call(item:, actor:)
      end
    end
  end
end
