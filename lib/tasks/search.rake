# frozen_string_literal: true

namespace :search do
  desc "Rebuild item search projections (search_text + embeddings) for every tenant"
  task reindex: :environment do
    TenantSweep.in_each_tenant do |slug|
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
