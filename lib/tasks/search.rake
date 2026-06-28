# frozen_string_literal: true

namespace :search do
  desc "Rebuild item search projections (search_text + embeddings) for every tenant"
  task reindex: :environment do
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        count = 0
        Item.includes(box: :room).find_each do |item|
          Search::RefreshDocument.new.call(item: item)
          count += 1
        end
        Rails.logger.info("[search:reindex] #{slug}: #{count} items")
        puts "[search:reindex] #{slug}: #{count} items"
      end
    end
  end
end
