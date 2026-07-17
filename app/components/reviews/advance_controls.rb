# frozen_string_literal: true

module Components
  module Reviews
    # #660 — the review walk's advance controls, rendered at the items panel's
    # header (compact) and footer (full-width, stacked) so a long item list never
    # buries them. When the Move is editable and the photo still has something to
    # confirm, the pair renders: "Mark as Reviewed" (POST) confirms + advances,
    # "Ignore" advances unchanged. Otherwise (a read-only walk, or a photo with
    # nothing pending) the single navigation link keeps its honest Next/Finish
    # label. Both hrefs arrive precomputed from ReviewsController
    # (advance_href_for — the single home of the walk's URL grammar), so this
    # component is pure presentation. State is a render-time snapshot: removing
    # or renaming an item in place doesn't re-render these controls, and a stale
    # "Mark as Reviewed" is a harmless idempotent no-op that still advances.
    class AdvanceControls < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs advance_href: untyped
      # @rbs mark_href: untyped
      # @rbs next_photo: untyped
      # @rbs editable: untyped
      # @rbs pending_review: untyped
      # @rbs compact: untyped
      # @rbs return: void
      def initialize(advance_href:, mark_href:, next_photo:, editable:, pending_review:, compact:)
        @advance_href = advance_href
        @mark_href = mark_href
        @next_photo = next_photo
        @editable = editable
        @pending_review = pending_review
        @compact = compact
      end

      #: () -> void
      def view_template
        if @editable && @pending_review
          div(class: @compact ? "flex flex-shrink-0 items-center gap-2" : "flex flex-col gap-2") do
            mark_reviewed_button
            ignore_link
          end
        else
          advance_link(@next_photo ? "reviews.photo.next" : "reviews.photo.finish")
        end
      end

      private

      #: () -> untyped
      def mark_reviewed_button
        button_to(@mark_href, method: :post, form_class: @compact ? "" : "w-full",
                              class: classes(:primary)) do
          render Components::Icons::Check.new(css: "h-4 w-4")
          plain I18n.t("reviews.photo.mark_reviewed")
        end
      end

      # Advancing without marking — the same navigation the old "Next Photo" did,
      # under a label that says what it means.

      #: () -> untyped
      def ignore_link
        a(href: @advance_href, class: classes(:secondary)) do
          plain I18n.t("reviews.photo.ignore")
          render Components::Icons::ChevronRight.new(css: "h-4 w-4")
        end
      end

      #: (untyped key) -> untyped
      def advance_link(key)
        a(href: @advance_href, class: classes(:primary)) do
          plain I18n.t(key)
          render Components::Icons::ChevronRight.new(css: "h-4 w-4")
        end
      end

      # One pill vocabulary for every advance control: sage-filled primary,
      # outlined secondary; compact (header) vs full-width (footer) sizing.

      #: (Symbol variant) -> String
      def classes(variant)
        size = @compact ? "px-4 py-2" : "w-full px-6 py-3"
        tint = if variant == :primary
                 "bg-accent-sage text-page hover:opacity-90"
               else
                 "border border-card-border bg-card text-text-warm " \
                   "hover:border-accent-sage hover:text-accent-sage"
               end
        "inline-flex items-center justify-center gap-2 rounded-full text-sm font-bold " \
          "transition active:scale-[0.98] #{size} #{tint}"
      end
    end
  end
end
