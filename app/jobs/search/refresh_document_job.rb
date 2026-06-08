# frozen_string_literal: true

module Search
  # Restores the Apartment tenant (jobs never inherit request Current/tenant) and
  # (re)builds one item's search projection — including the embedding, which is
  # why this is async (Domain §7.3). Safe if the item was since deleted.
  class RefreshDocumentJob < ApplicationJob
    queue_as :default

    def perform(item_id, tenant:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        item = Item.includes(:category, :tags, box: :room).find_by(id: item_id)
        next if item.nil?

        Search::RefreshDocument.new.call(item: item)
      end
    end
  end
end
