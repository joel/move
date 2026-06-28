# frozen_string_literal: true

module Boxes
  # Proposes a short contents description for a Box from its in-box items. Uses the
  # Move's own recognition provider (per-Move BYO — #185) for a natural summary, and
  # degrades to a deterministic, key-free join of the items' labels when no real
  # provider is configured or the vendor call fails. Always returns
  # Success(String) — a suggestion is advisory, so it never blocks or 500s. The
  # caller renders it into an editable field; nothing is persisted here.
  class SuggestDescription < BaseAction
    MAX_TERMS = 6

    def call(box:)
      items = digest_for(box)
      return Success("") if items.empty?

      unless ai_available?(box.move)
        emit(box, "deterministic")
        return Success(clamp(deterministic(items)))
      end

      begin
        text = RecognitionProviders.for_move(box.move).summarize_contents(items: items)
        emit(box, "ai")
        Success(clamp(text.presence || deterministic(items)))
      rescue StandardError # rubocop:disable Move/BroadRescue -- advisory AI; degrades to deterministic summary
        # Missing key, non-2xx, malformed body, or any raw Net::HTTP / TLS / DNS
        # transport failure (EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError, a
        # timeout, …) degrades to the deterministic summary. The scope is just the
        # vendor call, so a bug in our own digest/fallback still surfaces. A
        # suggestion is advisory: it must never 500 or block the box page.
        emit(box, "fallback")
        Success(clamp(deterministic(items)))
      end
    end

    private

    # Never hand back a suggestion the Box would reject on length — otherwise the
    # seal modal / form pre-fills an invalid value and the seal/update fails
    # validation with a generic error. Truncate (incl. ellipsis) to the Box cap.
    def clamp(text)
      text.to_s.truncate(Box::DESCRIPTION_MAX_LENGTH)
    end

    # In-box items as { label: }.
    def digest_for(box)
      box.items.in_box.ordered.map { |item| { label: item.name } }
    end

    # A real provider selected AND this Move's key present (strict BYO). `fake` and
    # an unconfigured real provider both take the deterministic path.
    def ai_available?(move)
      move.recognition_provider != "fake" && move.recognition_ready?
    end

    # Key-free summary: distinct item labels, in item order, capped and comma-joined.
    def deterministic(items)
      items.map { |i| i[:label].to_s.strip }.compact_blank.uniq.first(MAX_TERMS).join(", ")
    end

    def emit(box, source)
      Rails.event.notify(
        "box.description_suggested", box_id: box.id, move_id: box.move_id, source: source
      )
    end
  end
end
