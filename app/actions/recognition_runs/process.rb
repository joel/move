# frozen_string_literal: true

module RecognitionRuns
  # Runs the provider for a queued RecognitionRun and persists normalized results:
  # each detection becomes a RecognitionSuggestion + an Item, split by the Move's
  # auto-confirm threshold into auto_confirmed vs pending_review. No raw vendor
  # data or bounding boxes are stored. Provider/persistence errors end the run
  # `failed` (never stuck in processing) and return Failure — they never raise up.
  class Process < BaseAction
    def call(run:, provider: RecognitionProviders.resolve)
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
    rescue StandardError => e
      fail_run(run, e)
      Failure(run)
    end

    private

    def mark_processing(run)
      run.update!(status: "processing", started_at: Time.current)
      Rails.event.notify("recognition_run.processing", recognition_run_id: run.id)
    end

    # Feed the move's managed vocabulary to the provider so the model can fit
    # each detection into an existing category/tag rather than inventing names.
    def context(run)
      {
        room: run.box.room&.name,
        categories: run.move.categories.order(:name).pluck(:name),
        tags: run.move.tags.for_items.order(:name).pluck(:name)
      }
    end

    def materialize(run, result)
      threshold = run.move.auto_confirm_threshold.to_f
      result.objects.each { |object| materialize_one(run, object, threshold) }
    end

    # Suggestion + Item per detection, cross-linked. Above threshold → auto-confirmed.
    # No-overwrite guarantee (Domain §6.4): if the box already holds a *confirmed*
    # item of the same name, a late run must NOT overwrite it or silently add a
    # duplicate — record the detection as a `conflict` suggestion linked to the
    # existing item and leave it for human resolution in the review queue (D6).
    def materialize_one(run, object, threshold)
      quantity = [object.count.to_i, 1].max
      category = resolve_category(run.move, object.category)
      existing = confirmed_match(run.box, object.label)
      return conflict_suggestion(run, object, quantity, existing, category) if existing

      auto = object.confidence.present? && object.confidence >= threshold
      suggestion = run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media,
        proposed_name: object.label, proposed_quantity: quantity,
        proposed_category: category, proposed_fragile: object.fragile,
        confidence_score: object.confidence, state: auto ? "auto_accepted" : "pending"
      )
      item = run.box.items.create!(
        move: run.move, source_media: run.media, source_recognition_suggestion_id: suggestion.id,
        name: object.label, quantity: quantity, confidence_score: object.confidence,
        category: category, fragile: object.fragile,
        created_via: "recognition", review_state: auto ? "auto_confirmed" : "pending_review"
      )
      suggestion.update!(item: item)
      # Drives the D8 search projection (Search::IndexSubscriber).
      Rails.event.notify(
        "item.created", item_id: item.id, box_id: run.box_id, move_id: run.move_id, created_via: "recognition"
      )
    end

    # A user-confirmed item with the same name already lives in this box.
    def confirmed_match(box, label)
      box.items.where(review_state: "confirmed")
         .where("LOWER(name) = ?", label.to_s.strip.downcase).first
    end

    # Record the duplicate detection as a conflict without touching the existing
    # item or adding a second inventory row. The model's proposed category +
    # fragility ride along on the suggestion for the reviewer to apply.
    def conflict_suggestion(run, object, quantity, existing, category)
      run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media, item: existing,
        proposed_name: object.label, proposed_quantity: quantity,
        proposed_category: category, proposed_fragile: object.fragile,
        confidence_score: object.confidence, state: "conflict"
      )
    end

    # Best-effort map of the model's category name onto the Move's managed
    # vocabulary: reuse an existing category (case-insensitive) when one fits,
    # otherwise grow the vocabulary with the new name. Blank → nil (uncategorised).
    # Mirrors Vocabularies::Create's race handling (the lower(name) unique index
    # catches a concurrent insert; re-find the winner instead of 500ing).
    def resolve_category(move, name)
      name = name.to_s.strip
      return nil if name.blank?

      existing = move.categories.where("LOWER(name) = ?", name.downcase).first
      return existing if existing

      created = move.categories.create!(name: name)
      Rails.event.notify(
        "vocabulary.created", kind: "category", record_id: created.id, move_id: move.id, actor_id: nil
      )
      created
    rescue ActiveRecord::RecordNotUnique
      move.categories.where("LOWER(name) = ?", name.downcase).first
    end

    def finish(run, result)
      run.update!(
        status: "succeeded", completed_at: Time.current,
        provider_model: result.provider_model,
        metadata: run.metadata.merge("item_count" => result.objects.size, "provider" => result.provider)
      )
      Rails.event.notify("recognition_run.succeeded", recognition_run_id: run.id, item_count: result.objects.size)
    end

    def fail_run(run, error)
      run.update!(
        status: "failed", completed_at: Time.current,
        error_code: error.class.name, error_message: error.message.to_s.truncate(500)
      )
      Rails.event.notify("recognition_run.failed", recognition_run_id: run.id, error_code: error.class.name)
    end
  end
end
