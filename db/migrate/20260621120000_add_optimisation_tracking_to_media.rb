# frozen_string_literal: true

# Phase 42 — Image Optimisation. Tracks whether a Media blob has been downscaled
# to the bounded master (idempotency for the `images:optimize` backfill and a
# skip-flag for freshly-captured media), plus the pre-optimisation byte size so
# the backfill can report storage reclaimed.
class AddOptimisationTrackingToMedia < ActiveRecord::Migration[8.1]
  def change
    change_table :media, bulk: true do |t|
      t.datetime :optimized_at
      t.bigint :original_byte_size
    end
  end
end
