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
      # Materialize atomically: if any detection fails to persist, roll back all
      # of them so a failed run never leaves partial inventory behind.
      ActiveRecord::Base.transaction { materialize(run, result) }
      finish(run, result)
      Success(run)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- any failure marks the run failed (Failure)
      fail_run(run, e)
      Failure(run)
    end

    private

    #: (untyped run) -> untyped
    def mark_processing(run)
      run.update!(status: "processing", started_at: Time.current)
      Rails.event.notify("recognition_run.processing", recognition_run_id: run.id)
    end

    # The room is the only vocabulary the model is given as context — it nudges the
    # labels without inventing a per-item taxonomy (category/tags were removed).

    #: (untyped run) -> Hash[Symbol, untyped]
    def context(run)
      { room: run.box.room&.name }
    end

    #: (untyped run, untyped result) -> untyped
    def materialize(run, result)
      threshold = run.move.auto_confirm_threshold.to_f
      result.objects.each { |object| materialize_one(run, object, threshold) }
    end

    # Suggestion + Item per detection, cross-linked. Above threshold → auto-confirmed.
    # No-overwrite guarantee (Domain §6.4): if the box already holds a *confirmed*
    # item of the same name, a late run must NOT overwrite it or silently add a
    # duplicate — record the detection as a `conflict` suggestion linked to the
    # existing item and leave it for human resolution in the review queue (D6).

    #: (untyped run, untyped object, Float threshold) -> untyped
    def materialize_one(run, object, threshold)
      existing = confirmed_match(run.box, object.label)
      return conflict_suggestion(run, object, existing) if existing

      auto = object.confidence.present? && object.confidence >= threshold
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
    end

    # A user-confirmed item with the same name already lives in this box.

    #: (untyped box, untyped label) -> untyped
    def confirmed_match(box, label)
      box.items.where(review_state: "confirmed")
         .where("LOWER(name) = ?", label.to_s.strip.downcase).first
    end

    # Record the duplicate detection as a conflict without touching the existing
    # item or adding a second inventory row, for the reviewer to resolve.

    #: (untyped run, untyped object, untyped existing) -> untyped
    def conflict_suggestion(run, object, existing)
      run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media, item: existing,
        proposed_name: object.label,
        confidence_score: object.confidence, state: "conflict"
      )
    end

    #: (untyped run, untyped result) -> untyped
    def finish(run, result)
      run.update!(
        status: "succeeded", completed_at: Time.current,
        provider_model: result.provider_model,
        metadata: run.metadata.merge("item_count" => result.objects.size, "provider" => result.provider)
      )
      Rails.event.notify("recognition_run.succeeded", recognition_run_id: run.id, item_count: result.objects.size)
    end

    #: (untyped run, untyped error) -> untyped
    def fail_run(run, error)
      run.update!(
        status: "failed", completed_at: Time.current,
        error_code: error.class.name, error_message: error.message.to_s.truncate(500)
      )
      Rails.event.notify("recognition_run.failed", recognition_run_id: run.id, error_code: error.class.name)
    end
  end
end
