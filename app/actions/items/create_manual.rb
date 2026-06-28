# frozen_string_literal: true

module Items
  # Creates an Item by hand inside a Box (Design Spec B3 / Domain §5.4). Manual
  # items carry no source media and are born **confirmed** (the user vouched for
  # them) unless the name validation fails. An item is just a name now. The caller
  # owns the tenant context and the writable-Move guard (controller).
  class CreateManual < BaseAction
    def call(box:, params:, creator:, source_media: nil, require_open: false)
      yield ensure_writable(box.move)
      yield ensure_open(box) if require_open
      item = yield with_responsible(creator) { persist(box, params, source_media) }
      yield emit_event(item, creator)
      Success(item)
    end

    private

    # A *pure* manual add (box-detail "Add manually" / the MCP add_item_to_box
    # tool) only makes sense while the box is open — the same gate as capture
    # (Box#capturable? is packing-only). The photo-correction callers (per-photo
    # review, recovery) leave `require_open` false so a mis-detection can still be
    # fixed on an already-captured photo after the box is sealed/in transit.
    def ensure_open(box)
      box.capturable? ? Success() : Failure(:not_capturable)
    end

    # `source_media` is set when the item is added during per-photo review so it
    # joins that photo's item list.
    def persist(box, params, source_media)
      item = box.items.create!(
        move: box.move,
        name: params[:name],
        source_media: source_media,
        created_via: "manual",
        review_state: "confirmed",
        presence_state: "in_box"
      )
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(item, creator)
      Rails.event.notify(
        "item.created", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        created_via: "manual", created_by_id: creator&.id
      )
      Success()
    end
  end
end
