# frozen_string_literal: true

module Components
  module Reviews
    # The conflicts a photo's latest run left to settle (#881): each detection
    # that matched an item already confirmed in this box, with a link to that
    # item and, for editors on a writable Move, the two calls a person can make —
    # "Same item" and "Keep both" (RecognitionSuggestions::ResolveConflict,
    # outcomes :same / :second). Read-only viewers see the links alone.
    # Rendered inside Components::Reviews::ItemList, so a resolution re-renders
    # the whole list in place (ReviewsController#dismiss_conflict / #keep_both_conflict).
    class ConflictList < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs conflicts: Array[untyped]
      # @rbs editable: untyped
      # @rbs queue: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, conflicts:, editable:, queue: false)
        @move = move
        @box = box
        @media = media
        @conflicts = conflicts
        @editable = editable
        @queue = queue
      end

      #: () -> void
      def view_template
        # Always stacked: the review panel is a narrow column at every width.
        ul(class: "flex w-full min-w-0 flex-col gap-3 text-left") do
          @conflicts.each { |suggestion| conflict_row(suggestion) }
        end
      end

      private

      #: (untyped suggestion) -> untyped
      def conflict_row(suggestion)
        li(id: "review-conflict-#{suggestion.id}",
           class: "flex min-w-0 flex-col gap-3 rounded-xl border border-card-border bg-surface-container p-3") do
          match_link(suggestion.item)
          controls(suggestion) if @editable
        end
      end

      #: (untyped item) -> untyped
      def match_link(item)
        a(href: move_item_path(@move, item),
          class: "flex min-w-0 flex-col gap-1 text-body-md text-text-warm transition hover:text-accent-sage") do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.conflict_matches") }
          span(class: "flex items-center gap-1 font-bold") do
            span(class: "min-w-0 break-words") { item.name }
            render Components::Icons::ChevronRight.new(css: "h-4 w-4 shrink-0")
          end
        end
      end

      #: (untyped suggestion) -> untyped
      def controls(suggestion)
        div(class: "flex flex-wrap gap-2") do
          resolve_button(I18n.t("reviews.photo.conflict_same"), dismiss_path(suggestion), :secondary)
          resolve_button(I18n.t("reviews.photo.conflict_keep_both"), keep_both_path(suggestion), :ghost)
        end
      end

      #: (String label, String path, Symbol variant) -> untyped
      def resolve_button(label, path, variant)
        button_to(label, path, method: :post, class: "#{Components::Ui::Button.classes(variant:)} whitespace-nowrap")
      end

      #: (untyped suggestion) -> String
      def dismiss_path(suggestion)
        move_box_review_dismiss_conflict_path(@move, @box, @media, suggestion, **queue_params)
      end

      #: (untyped suggestion) -> String
      def keep_both_path(suggestion)
        move_box_review_keep_both_conflict_path(@move, @box, @media, suggestion, **queue_params)
      end

      #: () -> Hash[Symbol, String]
      def queue_params
        @queue ? { queue: ReviewsController::QUEUE_PARAM } : {}
      end
    end
  end
end
