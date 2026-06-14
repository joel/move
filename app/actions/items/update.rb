# frozen_string_literal: true

module Items
  # Updates an Item's editable attributes (name, category, quantity, fragile,
  # tags) from the C3 detail/edit screen. A user edit is authoritative and is
  # never silently overwritten by recognition (Domain §6.4). Review and presence
  # state are independent axes changed by their own actions, not here. Category +
  # tags are selection-only. Caller owns tenant context + writable-Move guard.
  class Update < BaseAction
    include Items::FormResolution

    def call(item:, params:, editor:)
      yield ensure_writable(item.move)
      category = yield resolve_category(item.move, params[:category_id])
      tags = yield resolve_tags(item.move, params[:tag_ids])
      yield with_responsible(editor) { persist(item, params, category, tags) }
      yield emit_event(item, editor)
      Success(item)
    end

    private

    def persist(item, params, category, tags)
      ActiveRecord::Base.transaction do
        item.update!(
          name: params[:name],
          quantity: coerce_quantity(params[:quantity]),
          fragile: coerce_fragile(params[:fragile]),
          category: category
        )
        item.tags = tags
      end
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(item, editor)
      Rails.event.notify(
        "item.updated", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        editor_id: editor&.id
      )
      Success()
    end
  end
end
