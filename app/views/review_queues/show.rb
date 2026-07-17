# frozen_string_literal: true

module Views
  module ReviewQueues
    # Move-wide review queue (#654) — every photo still holding an unreviewed
    # co-located item, oldest first, plus a "Review all" entry into the cross-box
    # walk. Sibling of the Gallery (shared ViewToggle); renders inside the
    # AppLayout sidebar shell.
    class Show < Views::Base
      #: (move: untyped, media: untyped, pending_counts: untyped, ?over_cap: untyped, ?had_reviewable: untyped, ?leftover_unreviewed: untyped) -> void
      def initialize(move:, media:, pending_counts:, over_cap: false, had_reviewable: false,
                     leftover_unreviewed: 0)
        @move = move
        @media = media
        @pending_counts = pending_counts
        @over_cap = over_cap
        @had_reviewable = had_reviewable
        # Unreviewed items with no walkable photo (resolved on the item page) —
        # keeps the caught-up copy honest while the entry badges count them.
        @leftover_unreviewed = leftover_unreviewed
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          render Components::Gallery::ViewToggle.new(move: @move, active: "review")
          cap_notice if @over_cap
          if @media.any?
            review_all
            grid
          else
            empty_state
          end
        end
      end

      private

      #: () -> untyped
      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("review_queues.show.title"),
          subtitle: I18n.t("review_queues.show.subtitle")
        )
      end

      #: () -> untyped
      def cap_notice
        p(class: "text-body-md text-on-surface-variant") do
          I18n.t("review_queues.show.capped", count: ReviewQueuesController::CAP)
        end
      end

      # Entry into the cross-box walk: the oldest pending photo, in queue mode.

      #: () -> untyped
      def review_all
        div do
          first = @media.fetch(0)
          a(
            href: move_box_review_photo_path(@move, first.box, first, queue: "move"),
            class: "inline-flex items-center justify-center gap-2 rounded-full bg-accent-sage " \
                   "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]"
          ) do
            plain I18n.t("review_queues.show.review_all")
            render Components::Icons::ChevronRight.new(css: "h-4 w-4")
          end
        end
      end

      #: () -> untyped
      def grid
        render Components::ReviewQueue::Grid.new(
          move: @move, media: @media, pending_counts: @pending_counts
        )
      end

      # Caught-up (the Move has review-walkable photos, none pending) vs
      # never-had-photos — a queue that empties by being worked deserves a
      # different message than one that never filled. Leftover pending items
      # win over the photo-history branch: even a Move with NO reviewable
      # photo must not say "nothing to review" while the entry badges count
      # photo-less pending items (Codex review, PR #655).

      #: () -> untyped
      def empty_state
        if @had_reviewable || @leftover_unreviewed.to_i.positive?
          render Components::Ui::EmptyState.new(
            icon: Components::Icons::Check,
            title: I18n.t("review_queues.show.empty.caught_up_title"),
            description: caught_up_description
          ) do
            render Components::Ui::Button.new(
              label: I18n.t("review_queues.show.empty.browse_gallery"),
              href: move_gallery_path(@move),
              variant: :ghost
            )
          end
        else
          render Components::Ui::EmptyState.new(
            icon: Components::Icons::Camera,
            title: I18n.t("review_queues.show.empty.title"),
            description: I18n.t("review_queues.show.empty.description")
          )
        end
      end

      # "Every detected item has been reviewed" would lie while photo-less /
      # moved-away pending items still count in the entry badges — those are
      # resolved from their item pages (#146), so say so.

      #: () -> String
      def caught_up_description
        if @leftover_unreviewed.to_i.positive?
          I18n.t("review_queues.show.empty.caught_up_leftover", count: @leftover_unreviewed)
        else
          I18n.t("review_queues.show.empty.caught_up_description")
        end
      end
    end
  end
end
