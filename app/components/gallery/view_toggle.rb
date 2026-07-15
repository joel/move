# frozen_string_literal: true

module Components
  module Gallery
    # Photos | Groups | To review segmented toggle (#633, #654) — pill links in
    # the gallery's chip vocabulary. Photos/Groups are GET-param driven
    # (?view=groups); To review is its own surface (the Move-wide review queue).
    # All bookmarkable. Rendered by both gallery views and the review queue,
    # each declaring which pill is active.
    class ViewToggle < Components::Base
      #: (move: untyped, active: untyped) -> void
      def initialize(move:, active:)
        @move = move
        @active = active
      end

      #: () -> void
      def view_template
        nav(aria_label: I18n.t("galleries.toggle.label"), class: "flex gap-3") do
          toggle_link(I18n.t("galleries.toggle.photos"), move_gallery_path(@move), @active == "photos")
          toggle_link(
            I18n.t("galleries.toggle.groups"),
            move_gallery_path(@move, view: "groups"),
            @active == "groups"
          )
          toggle_link(I18n.t("galleries.toggle.to_review"), move_review_path(@move), @active == "review")
        end
      end

      private

      #: (untyped label, untyped href, bool selected) -> untyped
      def toggle_link(label, href, selected)
        a(href: href, class: "flex-shrink-0", aria_current: selected ? "page" : nil) do
          render Components::Ui::Chip.new(label: label, kind: :room, selected: selected)
        end
      end
    end
  end
end
