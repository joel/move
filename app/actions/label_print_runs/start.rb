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
    # How big a single bulk print job may be (the domain guard, kept in the action
    # layer — AGENTS.md §1 #2). MAX_LABELS caps boxes; MAX_PAGES caps total PDF
    # *pages* (boxes × copies) since GenerateJob renders the whole document into
    # memory — the page count, not the box count, is the real CPU/memory/storage
    # driver (#312). 400 = the prior worst case (200 boxes × the old fixed 2 copies),
    # so a high labels_per_box can't multiply the workload (was 2,000 at 200 × 10).
    MAX_LABELS = 200
    MAX_PAGES = 400
    # Soft warning threshold: a run generating more than this many labels
    # (boxes × copies) asks the user to confirm before printing, so an accidental
    # large range can't silently burn thermal paper (#314). Below the hard caps
    # above — this is a prompt, not a rejection.
    WARN_LABELS = 50

    # Effective box cap for a Move's labels_per_box: the lesser of the box cap and
    # the page budget. copies is 1..10 (Move-validated); floored to ≥1 so a bad
    # value can't divide by zero.
    def self.box_cap(copies)
      [MAX_LABELS, MAX_PAGES / [copies.to_i, 1].max].min
    end

    def call(move:, from:, to:, host:, protocol:, confirmed: false)
      return Failure(:invalid_range) if from.nil? || to.nil? || from > to

      cap = self.class.box_cap(move.labels_per_box)

      # Snapshot the exact box ids now (SQL, in print order). The job renders THIS
      # set, not a re-query of the mutable range — so total_count, the cap, and the
      # rendered PDF always agree even if boxes are added/deleted/renumbered while
      # the job waits in the queue (mirrors IndexingRuns::Start). LIMIT cap+1 bounds
      # the load: an over-cap range fetches one extra id and is rejected, never
      # materializing every id of an intentionally broad range.
      box_ids = move.boxes.in_number_range(from, to).limit(cap + 1).ids
      return Failure(:empty) if box_ids.empty?
      return Failure(:too_many) if box_ids.size > cap

      # A large batch asks for confirmation first; the controller renders the Hash
      # payload as a prompt (array payloads break dry-monads pattern matching).
      prompt = confirmation_prompt(box_ids.size, move.labels_per_box, confirmed)
      return Failure(prompt) if prompt

      run = move.label_print_runs.create!(
        from_number: from, to_number: to, total_count: box_ids.size,
        status: "processing", started_at: Time.current
      )
      enqueue(run, box_ids, host, protocol)
      Success(run)
    end

    private

    # The confirm payload when a run would print more than WARN_LABELS labels and the
    # user hasn't confirmed yet, else nil (small batch, or already confirmed).
    def confirmation_prompt(boxes, copies, confirmed)
      labels = boxes * copies
      return if confirmed || labels <= WARN_LABELS

      { confirm: true, boxes:, copies:, labels: }
    end

    def enqueue(run, box_ids, host, protocol)
      # Snapshot labels_per_box at click time (like box_ids/host) so a Settings
      # change while the job waits in the queue can't alter the in-flight PDF (#303).
      GenerateJob.perform_later(
        run.id, tenant: Apartment::Tenant.current, host:, protocol:,
                box_ids:, copies: run.move.labels_per_box
      )
    end
  end
end
