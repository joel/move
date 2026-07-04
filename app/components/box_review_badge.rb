# frozen_string_literal: true

module Components
  # B1 — the permanent "review items" badge above the box gallery, linking into the
  # C2 per-photo review walk. Sage (success) once every item is reviewed, tertiary
  # (the app-wide pending_review colour) while items still await review. Rendered
  # only when the box has a review-walkable photo (BoxesController#show computes
  # that as `reviewable`), so the access stays permanent rather than vanishing the
  # moment the last item is confirmed.
  class BoxReviewBadge < Components::Base
    REVIEWED_TINT = "bg-accent-sage/15 text-accent-sage hover:bg-accent-sage/25"
    PENDING_TINT = "bg-tertiary/15 text-tertiary hover:bg-tertiary/25"

    #: (move: untyped, box: untyped, pending_count: untyped) -> void
    def initialize(move:, box:, pending_count:)
      @move = move
      @box = box
      @pending_count = pending_count
    end

    # Prefetch off: opening a photo marks its items reviewed, so hover must not
    # confirm them prematurely.

    #: () -> void
    def view_template
      reviewed = @pending_count.zero?
      a(href: move_box_review_path(@move, @box), data: { turbo_prefetch: "false" },
        class: "inline-flex items-center gap-1.5 rounded-full px-3 py-1 " \
               "text-label-caps uppercase transition #{reviewed ? REVIEWED_TINT : PENDING_TINT}") do
        if reviewed
          render Components::Icons::Check.new(css: "h-4 w-4")
          plain I18n.t("boxes.show.review_complete")
        else
          plain I18n.t("boxes.show.pending_review", count: @pending_count)
        end
      end
    end
  end
end
