# frozen_string_literal: true

module Search
  # Shared by actions that change an item's *denormalized* search context (box
  # number/room, category/tag/room name, vocab removal) without touching the item
  # rows themselves — so Item#after_commit won't fire. They enqueue a projection
  # refresh for the affected items (Domain §7.3).
  module Reindexing
    private

    def reindex_items(item_ids)
      tenant = Apartment::Tenant.current
      Array(item_ids).uniq.each do |id|
        Search::RefreshDocumentJob.perform_later(id, tenant: tenant)
      end
    end

    # Item ids whose search_text embeds this vocabulary value.
    def affected_item_ids(record)
      case record
      when Category, Tag then record.items.ids
      when Room then Item.where(box_id: record.boxes.select(:id)).ids
      else []
      end
    end
  end
end
