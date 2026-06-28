# frozen_string_literal: true

module Items
  # Shared by Items::CreateManual and Items::Update: resolve the submitted
  # category and tags against the Move's managed vocabularies (selection-only —
  # an id outside the Move's set is rejected, never created here; vocabulary
  # management is D7).
  #
  # The resolve_* helpers return Dry::Monads results so the action can `yield`
  # them: Success(value) or Failure(:invalid_category|:invalid_tag).
  module FormResolution
    private

    def resolve_category(move, category_id)
      return Success(nil) if category_id.blank?

      category = move.categories.find_by(id: category_id)
      category ? Success(category) : Failure(:invalid_category)
    end

    def resolve_tags(move, tag_ids)
      ids = Array(tag_ids).compact_blank.uniq
      return Success([]) if ids.empty?

      # Box-only tags are not assignable to items (applies-to facet), so a
      # box-only id is rejected just like an out-of-Move id.
      tags = move.tags.for_items.where(id: ids)
      tags.size == ids.size ? Success(tags.to_a) : Failure(:invalid_tag)
    end
  end
end
