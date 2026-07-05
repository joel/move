# frozen_string_literal: true

# #563 — mark a media whose master blob is no longer readable (the #560 SeaweedFS
# corruption) so display surfaces render a "photo unavailable" placeholder instead
# of requesting a variant off the dead master (which 500s + retries regeneration
# every view). Default false; a backfill flips the known-corrupt rows.
class AddImageUnavailableToMedia < ActiveRecord::Migration[8.1]
  def change
    add_column :media, :image_unavailable, :boolean, null: false, default: false
  end
end
