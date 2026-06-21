# frozen_string_literal: true

module LabelPrintRuns
  # Starts a bulk label-print generation pass (#303): validates the box-number
  # range, snapshots the box COUNT in SQL (never by loading rows), creates the run,
  # and enqueues GenerateJob which renders the PDF and reports progress. Returns the
  # run on success, or a Failure the controller maps to the form's range errors.
  #
  # NOT guarded by ensure_writable: generating labels is a read-only intent (it only
  # reads boxes), like viewing a single label — allowed even on an archived Move; it
  # persists only a transient run, no domain content. The caller owns authorization
  # (Move membership). `host`/`protocol` come from the request so the job (which has
  # no request) can build the QR scan URLs against the org subdomain.
  class Start < BaseAction
    def call(move:, from:, to:, host:, protocol:)
      return Failure(:invalid_range) if from.nil? || to.nil? || from > to

      # Snapshot the exact box ids now (SQL, in print order). The job renders THIS
      # set, not a re-query of the mutable range — so total_count, the MAX_LABELS
      # cap, and the rendered PDF always agree even if boxes are added/deleted/
      # renumbered while the job waits in the queue (mirrors IndexingRuns::Start).
      box_ids = move.boxes.in_number_range(from, to).ids
      return Failure(:empty) if box_ids.empty?
      return Failure(:too_many) if box_ids.size > LabelPrintRun::MAX_LABELS

      run = move.label_print_runs.create!(
        from_number: from, to_number: to, total_count: box_ids.size,
        status: "processing", started_at: Time.current
      )
      GenerateJob.perform_later(
        run.id, tenant: Apartment::Tenant.current, host: host, protocol: protocol, box_ids: box_ids
      )
      Success(run)
    end
  end
end
