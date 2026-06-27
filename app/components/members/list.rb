# frozen_string_literal: true

module Components
  module Members
    # F1 — the current-members roster. Stable id so the controller can replace the
    # whole list after an add or a role change (rows re-sorted by role, the
    # affected member highlighted). There is always at least one member (the
    # creator / last admin can't be removed), so there's no empty state.
    class List < Components::Base
      ID = "members-list"

      def initialize(move:, memberships:, current_user_id:, highlight_id: nil)
        @move = move
        @memberships = memberships
        @current_user_id = current_user_id
        @highlight_id = highlight_id
      end

      def view_template
        section(id: ID, aria_label: I18n.t("members.index.current"), class: "flex flex-col gap-stack-gap") do
          h2(class: "text-headline-md text-text-warm") { I18n.t("members.index.current") }
          @memberships.each do |membership|
            render Components::Members::Row.new(
              move: @move, membership: membership, current_user_id: @current_user_id,
              highlight: membership.id == @highlight_id
            )
          end
        end
      end
    end
  end
end
