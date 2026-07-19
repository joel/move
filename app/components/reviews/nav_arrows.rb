# frozen_string_literal: true

module Components
  module Reviews
    # #699 — the review walk's prev/next navigation arrows, on the progress-bar
    # row. Pure navigation (GET, side-effect-free since #660), distinct from the
    # AdvanceControls actions: prev reaches already-marked photos in box mode
    # and still-pending photos in queue mode; auto-advance stays strictly
    # forward. Both hrefs arrive precomputed from ReviewsController#nav_href_for
    # (the walk's URL grammar), nil at a walk boundary — the disabled arrow is a
    # same-size faded span (role + aria-disabled + label) so the cluster never
    # shifts and the boundary stays perceivable to assistive tech. Both-nil (a
    # single-photo walk) renders nothing: a nav that can't navigate is dead
    # chrome. Both anchors carry the pending-add guard (#690) so in-progress
    # item edits are saved before navigating — the pending-add controller scope
    # is widened to the whole screen in Views::Reviews::Photo for exactly this.
    # (Third copy of the icon-arrow recipe — consolidation tracked in #696.)
    class NavArrows < Components::Base
      # @rbs prev_href: untyped -- nil at the start of the walk
      # @rbs next_href: untyped -- nil at the end of the walk
      # @rbs return: void
      def initialize(prev_href:, next_href:)
        @prev_href = prev_href
        @next_href = next_href
      end

      #: () -> void
      def view_template
        return if @prev_href.nil? && @next_href.nil?

        nav(aria_label: I18n.t("reviews.photo.nav.label"), class: "flex shrink-0 items-center gap-1") do
          arrow(@prev_href, "reviews.photo.nav.previous", css: "h-5 w-5 rotate-180")
          arrow(@next_href, "reviews.photo.nav.next", css: "h-5 w-5")
        end
      end

      private

      #: (untyped href, String key, css: String) -> untyped
      def arrow(href, key, css:)
        if href
          a(
            href: href,
            aria_label: I18n.t(key),
            data: { action: "click->pending-add#guardVisit" },
            class: "rounded-full p-2 text-muted transition hover:bg-surface-container-high hover:text-text-warm"
          ) { render Components::Icons::ChevronRight.new(css: css) }
        else
          # tabindex keeps the disabled link in the tab order (the APG disabled-
          # link pattern) so keyboard users encounter the boundary too.
          span(role: "link", tabindex: "0", aria_disabled: "true", aria_label: I18n.t(key),
               class: "rounded-full p-2 text-muted/40") do
            render Components::Icons::ChevronRight.new(css: css)
          end
        end
      end
    end
  end
end
