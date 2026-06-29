# frozen_string_literal: true

require "stringio"

module Items
  # Generates an illustrative image for a photo-less manual item and attaches it
  # as the item's source photo (the opt-in "✨ generate image", #416). Mirrors
  # Captures::Create's Media attach, but the bytes come from ImageProviders
  # (per-Move BYO key) instead of an upload. Best-effort: the caller (the job)
  # turns a Failure into an `item.image_generation_failed` event so the card
  # reverts — generation must never corrupt the item.
  class GenerateImage < BaseAction
    def call(item:, actor: nil)
      yield ensure_writable(item.move)
      yield ensure_generatable(item)
      # The claim is taken synchronously by the caller (ItemsController#generate_image)
      # before enqueue, so the in-flight state is observable when the response
      # renders; here we just generate, and release/clear the claim on the way out.
      media = generate_and_attach(item)
      emit_generated(item, media, actor) if media # nil = lost a concurrent race; the winner emitted
      Success(item)
    rescue ImageProviders::Base::MissingApiKey
      release(item)
      emit_failed(item, actor, :missing_key)
    rescue ProviderHttp::Error => e
      release(item)
      Rails.logger.warn("[items.generate_image] provider failed for item #{item.id}: #{e.message}")
      emit_failed(item, actor, :generation_failed)
    rescue ActiveRecord::RecordInvalid => e
      release(item)
      emit_failed(item, actor, e.record.errors)
    end

    private

    # Idempotent guard: never overwrite a photo (a real capture or an earlier
    # generation) — so a double-submit / re-run is a no-op, not a clobber.
    def ensure_generatable(item)
      return Failure(:already_has_image) if item.source_media_id.present?

      Success()
    end

    # Drop the claim so a failed generation can be retried immediately (success
    # clears it inside the attach transaction instead).
    def release(item)
      item.update_columns(image_generating_at: nil) # rubocop:disable Rails/SkipsModelValidations
    end

    def generate_and_attach(item)
      result = ImageProviders.for_move(item.move).generate(prompt: prompt_for(item))
      # Serialize concurrent generations and commit the Media + link atomically: a
      # double-submit (two tabs / a retry) can't double-attach or orphan a Media —
      # the loser re-checks under the row lock and discards its result. The lock's
      # transaction also rolls the Media back if the link fails, so no half-written
      # photo survives. (The vendor call is intentionally OUTSIDE the lock.)
      item.with_lock do
        next nil if item.source_media_id.present?

        media = build_media(item, result)
        item.update!(source_media: media, image_generating_at: nil) # link + clear the claim atomically
        media
      end
    end

    # Same per-tenant Active Storage attach as a capture, but tagged
    # captured_via: "generated" so it's never mistaken for a real photo and never
    # trips the recognition/prewarm pipeline (which keys off media.captured).
    def build_media(item, result)
      media = item.box.media.new(
        move: item.move, media_type: "image", captured_via: "generated",
        captured_at: Time.current, optimized_at: Time.current
      )
      media.image.attach(
        io: StringIO.new(result.image_bytes), filename: "generated-#{item.id}.png",
        content_type: result.content_type
      )
      media.save!
      media
    end

    def prompt_for(item)
      "A clean, well-lit product photo of #{item.name}, centered on a plain neutral " \
        "background, no text, no labels, no watermark."
    end

    def emit_generated(item, media, actor)
      Rails.event.notify(
        "item.image_generated", item_id: item.id, media_id: media.id,
                                box_id: item.box_id, move_id: item.move_id, actor_id: actor&.id
      )
    end

    # Emits the failure event (so the broadcast reverts the card to a retryable
    # state) AND returns the Failure — keeping every domain event in the action
    # layer (the job stays event-free; architecture fitness #297).
    def emit_failed(item, actor, reason)
      Rails.event.notify(
        "item.image_generation_failed", item_id: item.id,
                                        box_id: item.box_id, move_id: item.move_id, actor_id: actor&.id
      )
      Failure(reason)
    end
  end
end
