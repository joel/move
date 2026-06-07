# frozen_string_literal: true

module Items
  # Creates an Item by hand inside a Box (Design Spec B3 / Domain §5.4). Manual
  # items carry no source media and are born **confirmed** (the user vouched for
  # them) unless a field validation fails. Category + tags are selection-only
  # from the Move's managed vocabularies. The caller owns the tenant context and
  # the writable-Move guard (controller).
  class CreateManual < BaseAction
    include Items::FormResolution

    def call(box:, params:, creator:)
      category = yield resolve_category(box.move, params[:category_id])
      tags = yield resolve_tags(box.move, params[:tag_ids])
      item = yield persist(box, params, category, tags)
      yield emit_event(item, creator)
      Success(item)
    end

    private

    # Item creation and tag assignment share one transaction so a validation
    # failure leaves no half-tagged item.
    def persist(box, params, category, tags)
      item = nil
      ActiveRecord::Base.transaction do
        item = box.items.create!(
          move: box.move,
          name: params[:name],
          quantity: coerce_quantity(params[:quantity]),
          fragile: coerce_fragile(params[:fragile]),
          category: category,
          created_via: "manual",
          review_state: "confirmed",
          presence_state: "in_box"
        )
        item.tags = tags
      end
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
