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

    total = ActiveStorage::Blob.count
    checked = copied = present = unreadable = 0
    puts "[storage:backfill_to_r2] #{total} blobs — SeaweedFS -> R2"

    ActiveStorage::Blob.find_each(batch_size: 200) do |blob|
      checked += 1
      if dst.exist?(blob.key)
        present += 1
      else
        # Only an unreadable SOURCE (the #560 corruption) is skipped — an expected,
        # known-lost object. Everything else propagates.
        data =
          begin
            src.download(blob.key)
          rescue StandardError => e # rubocop:disable Move/BroadRescue -- a corrupt/missing source (#560) is skipped, not fatal
            unreadable += 1
            puts "[storage:backfill_to_r2] SKIP unreadable source key=#{blob.key} (#{e.class})"
            nil
          end
        # The upload is deliberately NOT rescued: a DESTINATION (R2) write failure
        # — auth, checksum rejection, a transient error — must abort the backfill
        # so operators never see a "DONE" that silently left blobs uncopied.
        if data
          dst.upload(blob.key, StringIO.new(data), checksum: blob.checksum, content_type: blob.content_type)
          copied += 1
        end
      end
      if (checked % 50).zero?
        puts "[storage:backfill_to_r2] progress checked=#{checked}/#{total} copied=#{copied} present=#{present} unreadable=#{unreadable}"
      end
    end

    puts "[storage:backfill_to_r2] DONE checked=#{checked} copied=#{copied} already_present=#{present} unreadable=#{unreadable}"
  end
end
