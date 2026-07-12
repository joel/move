# frozen_string_literal: true

module Components
  module Members
    # F1/D14 — the pending-invitations list (#608). Stable id (always rendered)
    # so the controller can replace the whole container: a fresh invitation
    # lands at the top (recency), highlighted; when nothing is pending the
    # section renders no chrome at all (UX rule #3 — nothing to manage, nothing
    # shown; the invite form is the affordance).
    class PendingInvitations < Components::Base
      ID = "pending-invitations"

      #: (move: untyped, invitations: untyped, ?highlight_id: untyped) -> void
      def initialize(move:, invitations:, highlight_id: nil)
        @move = move
        @invitations = invitations.to_a
        @highlight_id = highlight_id
      end

      #: () -> void
      def view_template
        div(id: ID) do
          section_body if @invitations.any?
        end
      end

      private

      #: () -> untyped
      def section_body
        section(
          aria_label: I18n.t("members.pending.title"),
          class: "flex flex-col gap-stack-gap"
        ) do
          h2(class: "text-headline-md text-text-warm") { I18n.t("members.pending.title") }
          @invitations.each do |invitation|
            render Components::Members::PendingRow.new(
              move: @move, invitation: invitation,
              highlight: invitation.id == @highlight_id
            )
          end
        end
      end
    end
  end
end
