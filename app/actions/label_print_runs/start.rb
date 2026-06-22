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

      # The effective box cap depends on labels_per_box: a run is bounded by total
      # PDF pages (boxes × copies), not boxes alone, since the job renders the whole
      # document into memory (#312). box_cap collapses both limits into one number.
      cap = LabelPrintRun.box_cap(move.labels_per_box)

      # Snapshot the exact box ids now (SQL, in print order). The job renders THIS
      # set, not a re-query of the mutable range — so total_count, the cap, and the
      # rendered PDF always agree even if boxes are added/deleted/renumbered while
      # the job waits in the queue (mirrors IndexingRuns::Start). LIMIT cap+1 bounds
      # the load: an over-cap range fetches one extra id and is rejected, never
      # materializing every id of an intentionally broad range.
      box_ids = move.boxes.in_number_range(from, to).limit(cap + 1).ids
      return Failure(:empty) if box_ids.empty?
      return Failure(:too_many) if box_ids.size > cap

      run = move.label_print_runs.create!(
        from_number: from, to_number: to, total_count: box_ids.size,
        status: "processing", started_at: Time.current
      )
      # Snapshot labels_per_box at click time (like box_ids/host) so a Settings
      # change while the job waits in the queue can't alter the in-flight PDF (#303).
      GenerateJob.perform_later(
        run.id, tenant: Apartment::Tenant.current, host: host, protocol: protocol,
                box_ids: box_ids, copies: move.labels_per_box
      )
      Success(run)
    end
  end
end
