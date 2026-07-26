# frozen_string_literal: true

module Items
  # Marks ALL of a photo's still-in-box items as removed in one step — the box
  # detail "Unpack photo" tap (#727). Most photos hold a single item, so the
  # photo is the natural unpacking unit; multi-item photos unpack their whole
  # set at once.
  #
  # Loops Items::MarkRemoved (which re-checks the unpacking phase and emits
  # item.removed per item) so the activity feed reads exactly as N checklist
  # taps would — no new event type, no new subscriber. Box-scoped on purpose:
  # an item moved to another box keeps its source_media_id, and unpacking THIS
  # box must not reach into that other box (mirrors the unpacked-badge
  # semantics in BoxesController#unpacked_media_ids).
  #
  # No wrapping transaction: the presence write cannot fail mid-loop (always a
  # valid enum value, no callbacks), and events must not outlive a rollback —
  # each success is durable, per the bulk best-effort convention.
  class MarkPhotoRemoved < BaseAction
    #: (box: untyped, media: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, media:, actor:)
      yield ensure_writable(box.move)
      # Guarded here too (not only via the per-item loop) so a photo whose
      # items are all already removed still fails correctly on a wrong phase.
      yield ensure_unpacking_phase(box)

      # :move/:box preloaded — the per-item MarkRemoved guards read both, and
      # the loop must not re-load them per item (Bullet).
      items = box.items.in_box.where(source_media_id: media.id)
                 .includes(:move, :box).order(:created_at, :id).to_a
      items.each { |item| yield MarkRemoved.new.call(item: item, actor: actor) }
      Success(items)
    end

    private

    #: (untyped box) -> Dry::Monads::Result[untyped, untyped]
    def ensure_unpacking_phase(box)
      return Failure(:wrong_phase) unless box.unpacking? || box.unpacked?

      Success()
    end
  end
end
