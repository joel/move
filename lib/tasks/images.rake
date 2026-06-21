# frozen_string_literal: true

namespace :images do
  desc "Optimise existing media blobs (downscale + recompress) and reclaim storage (Phase 42)"
  task optimize: :environment do
    require "stringio"

    # Re-encode one Media's blob to the optimised master; returns bytes reclaimed,
    # or nil if it was skipped (no attachment / undecodable). A lambda (not a
    # top-level def) so it doesn't leak a method into the global namespace.
    optimize = lambda do |media|
      next nil unless media.image.attached?

      old_blob = media.image.blob
      original_size = old_blob.byte_size
      normalized = ImageNormalizer.call(io: StringIO.new(old_blob.download), filename: old_blob.filename.to_s)
      media.image.attach(normalized)
      media.update!(optimized_at: Time.current, original_byte_size: original_size)

      new_size = media.image.blob.byte_size
      # Reclaim the previous blob if attach didn't already (replace usually purges);
      # guarded so we never double-purge or raise on an already-gone blob.
      old_blob.purge if old_blob.id != media.image.blob.id && ActiveStorage::Blob.exists?(old_blob.id)
      original_size - new_size
    rescue ImageNormalizer::UnsupportedFormat, ImageNormalizer::ImageTooLarge => e
      warn "[images:optimize] skip media #{media.id}: #{e.class} (#{e.message})"
      nil
    end

    grand_total = 0
    # Media lives in each tenant schema; ActiveStorage::Blob is shared (public),
    # so switch per tenant to find the rows, then operate on their blobs.
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        done = 0
        reclaimed = 0
        # with_discarded: soft-deleted photos still occupy storage, so optimise
        # them too. optimized_at IS NULL is the idempotency guard — a re-run skips
        # everything already processed (and freshly-captured media is pre-stamped).
        Media.with_discarded.where(optimized_at: nil).find_each do |media|
          saved = optimize.call(media)
          next if saved.nil?

          done += 1
          reclaimed += saved
        end
        grand_total += reclaimed
        line = "[images:optimize] #{slug}: #{done} optimised, " \
               "#{ActiveSupport::NumberHelper.number_to_human_size(reclaimed)} reclaimed"
        Rails.logger.info(line)
        puts line
      end
    end

    puts "[images:optimize] total reclaimed: " \
         "#{ActiveSupport::NumberHelper.number_to_human_size(grand_total)}"
  end
end
