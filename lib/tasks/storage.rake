# frozen_string_literal: true

namespace :storage do
  desc "Copy all readable Active Storage blobs from SeaweedFS to R2 (#567). Idempotent — safe to re-run."
  task backfill_to_r2: :environment do
    # Active Storage blobs are global (shared `public` schema), so one pass over
    # ActiveStorage::Blob covers every tenant, both attachments (Media#image +
    # variants, LabelPrintRun#document), and no Apartment switch is needed.
    # Idempotent: skips keys already in R2, so it doubles as the pre-cutover delta
    # pass. Corrupt/missing sources (the #560 loss) are logged and skipped so one
    # bad object can't stall the sweep.
    src = ActiveStorage::Blob.services.fetch(:seaweedfs)
    dst = ActiveStorage::Blob.services.fetch(:r2)
    $stdout.sync = true

    # The ONLY source reads we tolerate failing are the masters already known-lost
    # to the #560 corruption (flagged image_unavailable). Any OTHER download
    # failure means the SOURCE itself is unhealthy (auth / network / misconfig) —
    # in which case every blob would "fail" and, without this allowlist, the task
    # would mark the whole store unreadable and exit DONE with nothing copied.
    # Build the allowlist of known-lost blob keys up front so anything else aborts.
    expected_lost = Set.new
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        Media.where(image_unavailable: true).with_attached_image.find_each { |m| expected_lost << m.image.blob.key }
      end
    end
    puts "[storage:backfill_to_r2] #{expected_lost.size} known-lost keys allowlisted (skippable)"

    total = ActiveStorage::Blob.count
    checked = copied = present = unreadable = repointed = 0
    puts "[storage:backfill_to_r2] #{total} blobs — SeaweedFS -> R2"

    ActiveStorage::Blob.find_each(batch_size: 200) do |blob|
      checked += 1
      in_r2 = dst.exist?(blob.key)
      if in_r2
        present += 1
      else
        data =
          begin
            src.download(blob.key)
          rescue StandardError => e # rubocop:disable Move/BroadRescue -- only allowlisted known-lost keys are skipped; every other source failure re-raises
            # Tolerated ONLY for a known-lost key; any other source read failure
            # means the source is unhealthy → re-raise and abort the whole run.
            raise unless expected_lost.include?(blob.key)

            unreadable += 1
            puts "[storage:backfill_to_r2] SKIP known-lost key=#{blob.key} (#{e.class})"
            nil
          end
        # The upload is deliberately NOT rescued: a DESTINATION (R2) write failure
        # — auth, checksum rejection, a transient error — must abort the backfill
        # so operators never see a "DONE" that silently left blobs uncopied.
        if data
          dst.upload(blob.key, StringIO.new(data), checksum: blob.checksum, content_type: blob.content_type)
          copied += 1
          in_r2 = true
        end
      end

      # Repoint the blob ROW at r2 once its bytes are in R2. Active Storage
      # resolves each blob through its persisted `service_name`, NOT the app's
      # default, so without this an existing blob keeps serving from SeaweedFS
      # after cutover and emptying that bucket would break it despite the object
      # being in R2. Only unreadable/known-lost blobs (not in R2) stay unpointed.
      if in_r2 && blob.service_name != "r2"
        blob.update_column(:service_name, "r2") # rubocop:disable Rails/SkipsModelValidations -- deliberate: repoint the row, no callbacks needed
        repointed += 1
      end

      if (checked % 50).zero?
        puts "[backfill_to_r2] #{checked}/#{total} copied=#{copied} present=#{present} repointed=#{repointed} unreadable=#{unreadable}"
      end
    end

    puts "[storage:backfill_to_r2] DONE checked=#{checked} copied=#{copied} already_present=#{present} repointed=#{repointed} unreadable=#{unreadable}"
  end
end
