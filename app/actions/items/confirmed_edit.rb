# frozen_string_literal: true

module Items
  # Shared persistence for the two human name-edit surfaces — Update (the C3
  # detail form) and Rename (the C2 inline field). A human edit is authoritative
  # (Domain §6.4): it confirms the item (review_state "confirmed", no longer
  # machine-vouched) and, when the name genuinely changes, invalidates the
  # recognition model's photo-derived hidden family (#626) — the facet described
  # what the model saw, not what the user now says the item is, so it must stop
  # steering the search/cluster embedding. "Genuinely" excludes cosmetic edits:
  # a case- or whitespace-only change (auto-capitalization, a stray space on the
  # blur-auto-saving C2 field) keeps the facet, because clearing is permanent —
  # family is never re-derived for an existing item.
  module ConfirmedEdit
    private

    #: (untyped item, untyped name) -> Dry::Monads::Result[untyped, untyped]
    def persist_confirmed_edit(item, name)
      attrs = { name: name, review_state: "confirmed" } #: Hash[Symbol, untyped]
      attrs[:family] = nil if reclassified?(item, name)
      item.update!(**attrs)
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      # The failed update! left the unsaved confirmation (and a possibly-cleared
      # family) on the in-memory item; drop both so a re-rendered rejected form
      # can't flash a false "Confirmed" or lose the facet without a save. (The
      # edited fields stay dirty on purpose — the user corrects and resubmits.)
      e.record.restore_attributes(%i[review_state family])
      Failure(e.record.errors)
    end

    # A rename is a reclassification only when it changes more than case or
    # whitespace — cosmetic edits must not cost the item its hidden facet.

    #: (untyped item, untyped name) -> bool
    def reclassified?(item, name)
      !name.to_s.squish.casecmp?(item.name.to_s.squish)
    end
  end
end
