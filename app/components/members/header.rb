# frozen_string_literal: true

module Components
  module Members
    # F1 — the Members page header (title + the "Invite" CTA). The CTA anchors
    # to the always-rendered invite-by-email form (D14 #608) and is therefore
    # unconditional — previously it was gated on the org-candidate pool, which
    # left a real org with no spare users showing NO invite affordance at all.
    class Header < Components::Base
      ID = "members-header"

      #: (move: untyped) -> void
      def initialize(move:)
        @move = move
      end

      #: () -> void
      def view_template
        div(id: ID) do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("members.index.title"),
            subtitle: I18n.t("members.index.subtitle")
          ) do
            render Components::Ui::Button.new(
              label: I18n.t("members.index.invite"),
              icon: Components::Icons::Plus,
              href: "##{Components::Members::InviteForm::ID}"
            )
          end
        end
      end
    end
  end
end
