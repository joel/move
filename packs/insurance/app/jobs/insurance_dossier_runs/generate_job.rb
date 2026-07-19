# frozen_string_literal: true

require "stringio"

module InsuranceDossierRuns
  # Renders the insurance claim-dossier PDF in the background, reporting live
  # progress (#702). Restores the Apartment tenant (jobs never inherit the
  # request tenant), loads the snapshotted boxes + their in_box items in two
  # queries, builds InsuranceDossierPdf box-by-box — reporting each box via
  # RecordProgress (throttled to ~20 broadcasts) — then attaches the finished
  # PDF to the run and finalizes it. Mirrors LabelPrintRuns::GenerateJob.
  class GenerateJob < ApplicationJob
    queue_as :default

    # Raised when render-time items exceed the Start-validated cap (items can
    # be added to snapshotted boxes while the job queues) — the run must fail
    # loudly rather than blow the memory budget the cap protects.
    class TooManyItems < StandardError; end

    def perform(run_id, tenant:, box_ids:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        run = InsuranceDossierRun.find_by(id: run_id)
        return unless run&.in_progress? # gone, or a retry after it already finished/failed

        generate(run, box_ids)
      end
    end

    private

    def generate(run, box_ids)
      sections = build_sections(run.move, box_ids)
      step = [run.total_count / 20, 1].max
      pdf = InsuranceDossierPdf.new(move: run.move, sections: sections, thumbnails: ThumbnailCache.new)
                               .render do |done, total|
        RecordProgress.new.call(run_id: run.id, completed: done) if (done % step).zero? || done == total
      end
      run.document.attach(io: StringIO.new(pdf), filename: "insurance-claim-dossier.pdf",
                          content_type: "application/pdf")
      run.update!(status: "completed", completed_count: run.total_count, finished_at: Time.current)
      Broadcasting.broadcast_status(run)
      reap_if_deleted(run)
    rescue StandardError # rubocop:disable Move/BroadRescue -- mark failed + broadcast, then re-raise (no swallow)
      begin
        run.update!(status: "failed", finished_at: Time.current)
        Broadcasting.broadcast_status(run)
      rescue ActiveRecord::ActiveRecordError
        # The run row (or its whole tenant schema) vanished mid-job — nothing
        # to finalize; fall through to the reap so an attached PDF can't orphan.
      end
      reap_if_deleted(run)
      raise # Solid Queue records it; a retry no-ops (run no longer in_progress)
    end

    # The Move (or the whole tenant) can be deleted while this job renders:
    # Moves::Destroy / Accounts::Delete capture attachment ids BEFORE deleting
    # rows, so an attach landing after that capture would strand a sensitive
    # blob in the public schema forever — the run purge can't see it (row
    # gone) and the abandoned-blob sweep skips it (still attached). Re-check
    # after finalizing and reap our own work.

    def reap_if_deleted(run)
      return if InsuranceDossierRun.exists?(run.id)

      run.document.purge
    rescue ActiveRecord::StatementInvalid
      # Tenant schema dropped mid-job (account deletion): the run row is gone
      # with its schema — purge the attachment just written to public.
      run.document.purge
    end

    # Renders exactly the ids Start snapshotted (in box-number order), so the PDF
    # always matches total_count even if boxes changed since enqueue. One items
    # query (attachment + blob preloaded — ThumbnailCache reads both per unique
    # photo) + an in-memory partition of the loaded rows (sanctioned — not a
    # count). The cap is re-checked at render time: the snapshot bounds BOXES,
    # but items can grow inside them while the job queues, and the cap's whole
    # point is bounding the photo bytes this job is about to load.

    def build_sections(move, box_ids)
      items = move.items.in_box.where(box_id: box_ids).ordered
                  .includes(source_media: { image_attachment: :blob }).to_a
      raise TooManyItems, items.size.to_s if items.size > Start::MAX_ITEMS

      by_box = items.group_by(&:box_id)
      move.boxes.where(id: box_ids).ordered.includes(:room).map do |box|
        { box: box, items: by_box.fetch(box.id, []) }
      end
    end
  end
end
