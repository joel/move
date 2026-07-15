# frozen_string_literal: true

module RecognitionRuns
  # Runs the provider for a queued RecognitionRun and persists normalized results:
  # each detection becomes a RecognitionSuggestion + an Item, split by the Move's
  # auto-confirm threshold into auto_confirmed vs pending_review. No raw vendor
  # data or bounding boxes are stored. Provider/persistence errors end the run
  # `failed` (never stuck in processing) and return Failure — they never raise up.
  class Process < BaseAction
    #: (run: untyped, ?provider: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(run:, provider: nil)
      # Per-Move provider (#185): the active provider + key come from the Move, not
      # a global ENV setting. A real provider with no key fails fast in #identify
      # (Base::MissingApiKey) — the shared deployment key is never used. Injectable
      # for specs.
      provider ||= RecognitionProviders.for_move(run.move)

      # Drop in-flight recognition when the Move was archived after capture: an
      # archived Move is read-only, so don't process or persist anything. The run
      # is left `queued` (never enters `processing`) and the job no-ops. Plain
      # return (not `yield`) so the guard can't be swallowed by the rescue below.
      #
      # #120 decision (Option A): the run is intentionally left non-terminal
      # rather than written to `failed`/`cancelled` — the strictest read-only
      # behaviour is zero writes to a read-only Move. A lingering `queued` run is
      # invisible today (the capture surface is behind require_writable_move!, and
      # a run is not an Item so it never inflates pending-review counts), and there
      # is no Move-archive action in the app (archiving happens only via seeds /
      # console). If/when a `Moves::Archive` action is added, it should cancel
      # in-flight runs to a terminal state there — i.e. during the transition,
      # while the Move is still writable — which is the clean home for Option B.
      guard = ensure_writable(run.move)
      return guard if guard.failure?

      mark_processing(run)
      result = provider.identify(image: run.media.image, context: context(run))
      # Materialize AND complete atomically (#649): one commit covers the
      # items, suggestions, family backfills and the run's terminal
      # `succeeded` status. A failure anywhere before the commit — a
      # detection failing to persist, or the status write itself — rolls the
      # whole run back, so the rescue below records a failed run with ZERO
      # inventory, unconditionally: Retry (a new run, failed-only) can never
      # meet a failed run holding committed items. After the commit the
      # remaining work is announcement only (#announce, isolated). A crash
      # between commit and announce leaves a succeeded run: ProcessJob skips
      # the re-released execution and re-announces; only lost backfill events
      # stay lost (the search refresh waits for the item's next event). The
      # item.created events still fire inside the transaction (#648); the
      # backfill payloads are collected and emitted post-commit (#650 — a
      # backfill has no later event to correct a stale pre-commit read).
      backfilled = ActiveRecord::Base.transaction do
        payloads = materialize(run, result)
        complete(run, result)
        payloads
      end
      announce(run, result, backfilled)
      Success(run)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- any failure marks the run failed (Failure)
      fail_run(run, e)
      Failure(run)
    end

    private

    #: (untyped run) -> untyped
    def mark_processing(run)
      run.update!(status: "processing", started_at: Time.current)
      notify_isolated(run, "recognition_run.processing", { recognition_run_id: run.id })
    end

    # The room is the only vocabulary the model is given as context — it nudges the
    # labels without inventing a per-item taxonomy (category/tags were removed).

    #: (untyped run) -> Hash[Symbol, untyped]
    def context(run)
      { room: run.box.room&.name }
    end

    # Returns the item.family_backfilled payloads to emit after commit.

    #: (untyped run, untyped result) -> Array[Hash[Symbol, untyped]]
    def materialize(run, result)
      threshold = run.move.auto_confirm_threshold.to_f
      result.objects.filter_map { |object| materialize_one(run, object, threshold) }
    end

    # Suggestion + Item per detection, cross-linked. Above threshold → auto-confirmed.
    # No-overwrite guarantee (Domain §6.4): if the box already holds a *confirmed*
    # item of the same name, a late run must NOT overwrite it or silently add a
    # duplicate — record the detection as a `conflict` suggestion linked to the
    # existing item and leave it for human resolution in the review queue (D6).

    #: (untyped run, untyped object, Float threshold) -> Hash[Symbol, untyped]?
    def materialize_one(run, object, threshold)
      existing = confirmed_match(run.box, object.label)
      return conflict_suggestion(run, object, existing, threshold) if existing

      auto = confident?(object, threshold)
      suggestion = run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media,
        proposed_name: object.label,
        confidence_score: object.confidence, state: auto ? "auto_accepted" : "pending"
      )
      item = run.box.items.create!(
        move: run.move, source_media: run.media, source_recognition_suggestion_id: suggestion.id,
        name: object.label, confidence_score: object.confidence, family: object.family,
        created_via: "recognition", review_state: auto ? "auto_confirmed" : "pending_review"
      )
      suggestion.update!(item: item)
      # Drives the D8 search projection (Search::IndexSubscriber).
      Rails.event.notify(
        "item.created", item_id: item.id, box_id: run.box_id, move_id: run.move_id, created_via: "recognition"
      )
      nil
    end

    # The auto-confirm bar doubles as the trust bar for facet enrichment.

    #: (untyped object, Float threshold) -> bool
    def confident?(object, threshold)
      object.confidence.present? && object.confidence >= threshold
    end

    # A user-confirmed item with the same name already lives in this box.

    #: (untyped box, untyped label) -> untyped
    def confirmed_match(box, label)
      named(box.items.where(review_state: "confirmed"), label).first
    end

    # Case-insensitive current-name match — one predicate shared by conflict
    # detection and the backfill's write-time re-check, so the two can't drift.

    #: (untyped items, untyped label) -> untyped
    def named(items, label)
      items.where("LOWER(name) = ?", label.to_s.strip.downcase)
    end

    # Record the duplicate detection as a conflict without touching the existing
    # item's user-authored fields or adding a second inventory row, for the
    # reviewer to resolve. The one sanctioned write is the hidden-family
    # backfill below (#627).

    #: (untyped run, untyped object, untyped existing, Float threshold) -> Hash[Symbol, untyped]?
    def conflict_suggestion(run, object, existing, threshold)
      run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media, item: existing,
        proposed_name: object.label,
        confidence_score: object.confidence, state: "conflict"
      )
      backfill_family(run, object, existing, threshold)
    end

    # Opportunistic enrichment (#627): a confirmed item with no hidden family
    # (manual/MCP-created, or pre-#626) adopts the family of a detection whose
    # label matches its *current* name — the facet describes exactly the name
    # the item has now. Only a detection the Move would trust to auto-confirm
    # may enrich (confident?): the family is permanent once set and steers the
    # search/cluster embeddings, so a low-confidence guess must not stick. A
    # single guarded UPDATE re-checks `family IS NULL` and the name match at
    # write time, so it can never overwrite a non-nil family (Domain §6.4) and
    # a concurrent rename — which deliberately drops the family
    # (Items::ConfirmedEdit) — can't be undercut by this stale read.
    # updated_at is bumped so item cache keys (the C3 family rail) invalidate.

    #: (untyped run, untyped object, untyped existing, Float threshold) -> Hash[Symbol, untyped]?
    def backfill_family(run, object, existing, threshold)
      return nil if object.family.blank? || existing.family.present?
      return nil unless confident?(object, threshold)

      backfilled = named(run.box.items.where(id: existing.id, family: nil), object.label)
                   .update_all(family: object.family, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      return nil if backfilled.zero?

      # The payload for an item.family_backfilled event, emitted by #call after
      # the transaction commits (the refresh it triggers must read the committed
      # family — see #call). Refreshes the item's search document and requests a
      # cluster recompute (both subscribers whitelist the event); deliberately
      # absent from the activity feed — a hidden machine facet with no actor is
      # not a user story.
      { item_id: existing.id, box_id: run.box_id, move_id: run.move_id }
    end

    # The terminal transition rides the materialize transaction (#649): a run
    # reads `succeeded` if and only if its inventory committed with it.

    #: (untyped run, untyped result) -> untyped
    def complete(run, result)
      run.update!(
        status: "succeeded", completed_at: Time.current,
        provider_model: result.provider_model,
        metadata: run.metadata.merge("item_count" => result.objects.size, "provider" => result.provider)
      )
    end

    # Post-commit announcement: the inventory and the succeeded status are
    # already committed, so a dispatch failure must not reach the broad rescue
    # in #call — it would record a contradictory failed run and arm Retry to
    # duplicate the committed items (#649).

    #: (untyped run, untyped result, Array[Hash[Symbol, untyped]] backfilled) -> untyped
    def announce(run, result, backfilled)
      backfilled.each { |payload| notify_isolated(run, "item.family_backfilled", payload) }
      notify_isolated(run, "recognition_run.succeeded",
                      { recognition_run_id: run.id, item_count: result.objects.size })
    end

    # Every event this action emits goes through here so no subscriber can
    # fail the run over a side effect (§1#4). Subscribers self-isolate and the
    # production reporter swallows their errors anyway — this guards the
    # dev/test raise path (raise_on_error) and reporter-internal failures,
    # where an escape would be catastrophic: on the success path it would flip
    # a committed run to failed and arm Retry to duplicate its items; from the
    # rescue path it would leak the raise past the class contract. Failures
    # are Sentry-visible (error_reporter) and logged.

    #: (untyped run, String name, Hash[Symbol, untyped] payload) -> untyped
    def notify_isolated(run, name, payload)
      Rails.event.notify(name, payload)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4: an event dispatch failure must not change the run's committed fate
      Rails.logger.warn("[recognition] #{name} announcement failed for run=#{run.id}: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true)
    end

    #: (untyped run, untyped error) -> untyped
    def fail_run(run, error)
      run.update!(
        status: "failed", completed_at: Time.current,
        error_code: error.class.name, error_message: error.message.to_s.truncate(500)
      )
      notify_isolated(run, "recognition_run.failed",
                      { recognition_run_id: run.id, error_code: error.class.name })
    end
  end
end
