# frozen_string_literal: true

module RecognitionRuns
  # Runs the provider for a queued RecognitionRun and persists normalized results:
  # each detection becomes a RecognitionSuggestion + an Item, split by the Move's
  # auto-confirm threshold into auto_confirmed vs pending_review. No raw vendor
  # data or bounding boxes are stored. Provider/persistence errors end the run
  # `failed` (never stuck in processing) and return Failure — they never raise up.
  class Process < BaseAction
    def call(run:, provider: RecognitionProviders.resolve)
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

    def context(run)
      { room: run.box.room&.name }
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
      existing = confirmed_match(run.box, object.label)
      return conflict_suggestion(run, object, quantity, existing) if existing

      auto = object.confidence.present? && object.confidence >= threshold
      suggestion = run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media,
        proposed_name: object.label, proposed_quantity: quantity,
        confidence_score: object.confidence, state: auto ? "auto_accepted" : "pending"
      )
      item = run.box.items.create!(
        move: run.move, source_media: run.media, source_recognition_suggestion_id: suggestion.id,
        name: object.label, quantity: quantity, confidence_score: object.confidence,
        created_via: "recognition", review_state: auto ? "auto_confirmed" : "pending_review"
      )
      suggestion.update!(item: item)
    end

    # A user-confirmed item with the same name already lives in this box.
    def confirmed_match(box, label)
      box.items.where(review_state: "confirmed")
         .where("LOWER(name) = ?", label.to_s.strip.downcase).first
    end

    # Record the duplicate detection as a conflict without touching the existing
    # item or adding a second inventory row.
    def conflict_suggestion(run, object, quantity, existing)
      run.recognition_suggestions.create!(
        move: run.move, box: run.box, media: run.media, item: existing,
        proposed_name: object.label, proposed_quantity: quantity,
        confidence_score: object.confidence, state: "conflict"
      )
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
