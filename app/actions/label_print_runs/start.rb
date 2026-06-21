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

      count = move.boxes.in_number_range(from, to).count # SQL COUNT, not rows-into-Ruby
      return Failure(:empty) if count.zero?
      return Failure(:too_many) if count > LabelPrintRun::MAX_LABELS

      run = move.label_print_runs.create!(
        from_number: from, to_number: to, total_count: count,
        status: "processing", started_at: Time.current
      )
      GenerateJob.perform_later(run.id, tenant: Apartment::Tenant.current, host: host, protocol: protocol)
      Success(run)
    end
  end
end
