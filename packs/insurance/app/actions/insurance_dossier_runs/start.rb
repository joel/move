# frozen_string_literal: true

# pack_public: true -- public API of packs/insurance (the controller's entry point).
# Kept in the action layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module InsuranceDossierRuns
  # #702 — starts a claim-dossier generation pass: counts the in_box items in
  # SQL, snapshots the boxes that hold them (in number order), creates the run
  # and enqueues GenerateJob which renders the photo-heavy PDF and reports
  # progress. Returns the run, or a Failure the controller maps to a hub alert.
  #
  # NOT guarded by ensure_writable: generating the dossier is a read-only intent
  # (it only reads items/photos) — allowed even on an archived Move; it persists
  # only a transient run, no domain content. The caller owns authorization
  # (admin-only, MovePolicy#export_insurance_dossier?). No host/protocol plumbing:
  # unlike labels, the dossier contains no URLs.
  class Start < BaseAction
    # Hard cap on dossier size (the domain guard, AGENTS §1 #2). Like labels'
    # MAX_PAGES, the whole PDF is rendered into memory — here the real driver is
    # unique-photo bytes (each unique capture is downloaded + downscaled to a
    # ~15-25 KB thumbnail once), so 1,000 items is a ~25 MB worst-case document.
    MAX_ITEMS = 1_000

    #: (move: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, actor:)
      # Snapshot the exact box ids FIRST (SQL, number order, only boxes that
      # hold in_box items), then count items scoped to that same snapshot — one
      # direction of derivation, so a concurrent mutation can't mint a
      # "0 boxes · N items" run. The job renders THIS box set, not a re-query,
      # mirroring LabelPrintRuns::Start.
      box_ids = move.boxes.where(id: move.items.in_box.select(:box_id)).ordered.ids
      return Failure(:empty) if box_ids.empty?

      item_count = move.items.in_box.where(box_id: box_ids).count
      return Failure(:too_many) if item_count > MAX_ITEMS

      run = move.insurance_dossier_runs.create!(
        total_count: box_ids.size, item_count: item_count,
        status: "processing", started_at: Time.current
      )
      yield emit_event(run, actor)
      GenerateJob.perform_later(run.id, tenant: Apartment::Tenant.current, box_ids: box_ids)
      Success(run)
    end

    private

    # Emitted in the request (not the job) so the subscriber sees the right
    # Apartment tenant without plumbing, and the audit records WHO asked — the
    # audit-relevant fact for a sensitive export (Domain §12.3). The payload is
    # derived from the persisted run, so the audit trail can never disagree
    # with the record.

    #: (untyped run, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(run, actor)
      Rails.event.notify(
        "insurance.dossier_generated",
        move_id: run.move_id, actor_id: actor&.id, run_id: run.id,
        box_count: run.total_count, item_count: run.item_count
      )
      Success()
    end
  end
end
