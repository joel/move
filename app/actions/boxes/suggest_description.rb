# frozen_string_literal: true

module Boxes
  # Proposes a short contents description for a Box from its in-box items. Uses the
  # Move's own recognition provider (per-Move BYO — #185) for a natural summary, and
  # degrades to a deterministic, key-free join of the items' categories/labels when
  # no real provider is configured or the vendor call fails. Always returns
  # Success(String) — a suggestion is advisory, so it never blocks or 500s. The
  # caller renders it into an editable field; nothing is persisted here.
  class SuggestDescription < BaseAction
    MAX_TERMS = 6
    # Transport failures the vendor call can raise — all fall back to deterministic.
    TRANSPORT_ERRORS = [
      RecognitionProviders::Base::MissingApiKey, ProviderHttp::Error,
      Timeout::Error, SocketError
    ].freeze

    def call(box:)
      items = digest_for(box)
      return Success("") if items.empty?

      unless ai_available?(box.move)
        emit(box, "deterministic")
        return Success(deterministic(items))
      end

      text = RecognitionProviders.for_move(box.move).summarize_contents(items: items)
      emit(box, "ai")
      Success(text.presence || deterministic(items))
    rescue *TRANSPORT_ERRORS
      emit(box, "fallback")
      Success(deterministic(items))
    end

    private

    # In-box items as { label:, category:, count: }, category eager-loaded.
    def digest_for(box)
      box.items.in_box.includes(:category).ordered.map do |item|
        { label: item.name, category: item.category&.name, count: item.quantity }
      end
    end

    # A real provider selected AND this Move's key present (strict BYO). `fake` and
    # an unconfigured real provider both take the deterministic path.
    def ai_available?(move)
      move.recognition_provider != "fake" && move.recognition_ready?
    end

    # Key-free summary: distinct category names (falling back to the item label when
    # uncategorised), in item order, capped and comma-joined.
    def deterministic(items)
      items.map { |i| (i[:category].presence || i[:label]).to_s.strip }
           .compact_blank.uniq.first(MAX_TERMS).join(", ")
    end

    def emit(box, source)
      Rails.event.notify(
        "box.description_suggested", box_id: box.id, move_id: box.move_id, source: source
      )
    end
  end
end
