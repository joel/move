# frozen_string_literal: true

module Captures
  # Normalizes a pending capture off the request (#545): downloads the reserved
  # raw blob, runs ImageNormalizer (sniff → transcode → optimise master),
  # attaches the master, flips the Media to `ready`, enqueues recognition, emits
  # `media.captured` (which fans out to variant prewarm), and broadcasts the
  # refreshed panel. A processing failure flips the Media to `failed` (surfaced
  # in the panel) rather than leaving a stuck placeholder. Runs on the dedicated
  # image_ingest pool (#543). Idempotent: a retry once the media has left
  # `pending` no-ops.
  class IngestJob < ApplicationJob
    queue_as :image_ingest

    def perform(media_id, blob_id, captured_by_id:, tenant:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        media = Media.find_by(id: media_id)
        return unless media&.pending?
        # Zero writes on a read-only Move (#120): if the Move was archived after
        # capture-start, no-op — don't attach/ready/fail or enqueue recognition.
        # The row stays pending (harmless; hidden from the gallery by .ready), the
        # reserved blob is reaped by purge_abandoned_uploads. Mirrors
        # RecognitionRuns::Process leaving queued work untouched on archive.
        return unless media.move.writable?

        blob = ActiveStorage::Blob.find_by(id: blob_id)
        return mark_failed(media) if blob.nil?

        ingest(media, blob, captured_by_id)
        # FileNotFoundError: the blob row exists but its backing object is gone
        # (mirrors the synchronous Captures::Create rescue) — fail the tile, don't
        # leave it stuck pending.
      rescue ImageNormalizer::UnsupportedFormat, ImageNormalizer::ImageTooLarge,
             ActiveRecord::RecordInvalid, ActiveStorage::IntegrityError,
             ActiveStorage::FileNotFoundError => e
        Rails.logger.warn("[captures:ingest_job] media #{media_id} failed: #{e.class}: #{e.message}")
        mark_failed(media) if media
      end
    end

    private

    # Orchestrate only: normalize the bytes, hand the domain finalization (attach
    # → ready → recognition → media.captured event) to Captures::CompleteIngest
    # so the event stays in the action layer. A domain failure marks the row
    # failed rather than leaving a stuck placeholder.
    def ingest(media, blob, captured_by_id)
      normalized = ImageNormalizer.call({ io: StringIO.new(blob.download), filename: blob.filename.to_s })
      result = Captures::CompleteIngest.new.call(media: media, normalized: normalized, captured_by_id: captured_by_id)

      case result
      in Dry::Monads::Success(_)
        blob.purge_later
      in Dry::Monads::Failure(_)
        media.update!(status: "failed")
      end
      broadcast(media.box)
    end

    def mark_failed(media)
      media.update!(status: "failed")
      broadcast(media.box)
    end

    # Mirror the SessionBroadcastSubscriber: re-render the shared panel and push
    # it over the box's signed :recognition stream. A broadcast failure must
    # never fail the ingest.
    def broadcast(box)
      Turbo::StreamsChannel.broadcast_replace_to(
        box, :recognition,
        target: Views::Captures::SessionPanel::ID,
        html: ApplicationController.render(Captures::SessionContent.new(box).panel, layout: false)
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- broadcast must not break the ingest
      Rails.logger.warn("[captures:ingest_job] panel broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
