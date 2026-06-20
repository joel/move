# frozen_string_literal: true

module Search
  # Restores the Apartment tenant (jobs never inherit request Current/tenant) and
  # (re)builds one item's search projection — including the embedding, which is
  # why this is async (Domain §7.3). Safe if the item was since deleted.
  class RefreshDocumentJob < ApplicationJob
    queue_as :default

    def perform(item_id, tenant:, indexing_run_id: nil)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        item = Item.includes(:category, :tags, box: :room).find_by(id: item_id)
        outcome = :success
        begin
          # A since-deleted item still counts as "done" for the run's progress —
          # there is nothing left to embed.
          Search::RefreshDocument.new.call(item: item) if item
        rescue StandardError # rubocop:disable Move/BroadRescue -- tags outcome then re-raises (no swallow)
          outcome = :failure
          raise
        ensure
          # Part of a tracked re-embedding run (#239) → report this item finished
          # so the progress bar advances and the run can finalize. No-op otherwise.
          IndexingRuns::RecordProgress.new.call(run_id: indexing_run_id, outcome: outcome) if indexing_run_id
        end
      end
    end
  end
end
