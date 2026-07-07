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
    rescue ActiveStorage::Error => e
      # Expected operational failures only (missing blob / download / attach /
      # purge — ActiveStorage::FileNotFoundError, IntegrityError, …): log and skip
      # so one bad object doesn't strand the rest. A genuine code bug (any other
      # exception) still surfaces and aborts the run rather than being masked.
      warn "[images:optimize] skip media #{media.id} (storage): #{e.class} (#{e.message})"
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

  desc "One-off: purge orphaned Active Storage variant records + their stored objects (#572 decommission)"
  task cleanup_variants: :environment do
    # After the edge-transform cutover (#572) the app no longer generates Active
    # Storage display variants — the master is the only object we serve. Any
    # `active_storage_variant_records` (and their stored :thumb/:detail objects in
    # R2/SeaweedFS) left from the old MediaVariants::Prewarm pipeline are now dead
    # weight. Purge them. Idempotent: a re-run finds nothing.
    #
    # Blob/Attachment/VariantRecord are Apartment-EXCLUDED (shared `public` schema),
    # so this runs once against `public` — NOT per tenant. `variant.image.purge`
    # deletes the stored object + its attachment + blob rows; then the record goes.
    total = purged = 0
    ActiveStorage::VariantRecord.find_each do |record|
      total += 1
      begin
        record.image.purge if record.image.attached? # deletes the stored variant object
        record.destroy!
        purged += 1
      rescue ActiveStorage::Error, ActiveRecord::RecordNotDestroyed => e
        warn "[images:cleanup_variants] skip variant_record #{record.id}: #{e.class} (#{e.message})"
      end
    end

    line = "[images:cleanup_variants] purged #{purged}/#{total} variant records + their stored objects"
    Rails.logger.info(line)
    puts line
  end

  desc "Flag media whose master blob is unreadable so surfaces show a placeholder (#563)"
  task flag_unavailable: :environment do
    # Derives the corrupt set at RUNTIME rather than hardcoding ids and flags the
    # masters storage can't return (the #560 corruption). Env-safe — a no-op where
    # storage is healthy (dev/CI/test). Idempotent; only ever sets the flag (a
    # genuinely readable master is never re-hidden). with_discarded so soft-deleted
    # media (whose blobs are still swept by the R2 backfill) are flagged too.
    #
    # FULL=1 does a COMPLETE download of each master instead of the fast 64-byte
    # range probe. The probe only reads the head, so it MISSES blobs truncated at
    # the END (a SeaweedFS partial write): those pass the probe but fail a full
    # read and would abort storage:backfill_to_r2. Run `FULL=1 rake
    # images:flag_unavailable` before a backfill to catch the complete corrupt set;
    # the default probe is the cheap health check.
    require "timeout"
    full = ENV["FULL"].present?
    grand = 0
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        flagged = 0
        Media.with_discarded.ready.where(image_unavailable: false).with_attached_image.find_each do |media|
          blob = media.image.blob
          readable = begin
            if full
              Timeout.timeout(60) { blob.download }
            else
              Timeout.timeout(5) { blob.service.download_chunk(blob.key, 0..64) }
            end
            true
          rescue StandardError # rubocop:disable Move/BroadRescue -- any read error (corrupt/missing/timeout) means "can't display"
            false
          end
          next if readable

          # rubocop:disable Rails/SkipsModelValidations -- deliberate: flip one flag
          # across many rows; re-running image validations here is needless overhead.
          media.update_column(:image_unavailable, true)
          # rubocop:enable Rails/SkipsModelValidations
          flagged += 1
        end
        grand += flagged
        line = "[images:flag_unavailable] #{slug}: #{flagged} flagged unavailable"
        Rails.logger.info(line)
        puts line
      end
    end

    puts "[images:flag_unavailable] total: #{grand} media flagged unavailable"
  end
end
