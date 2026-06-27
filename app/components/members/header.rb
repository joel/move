# frozen_string_literal: true

module Components
  module Members
    # F1 — the Members page header (title + the "Invite" CTA). Stable id so the
    # controller can re-stream it whenever the candidate pool changes: the Invite
    # button only earns its place while there's someone left to add, so it must
    # appear/disappear in lockstep with the add-member form (UX rule #3).
    class Header < Components::Base
      ID = "members-header"

      def initialize(move:, candidates:)
        @move = move
        @candidates = candidates.to_a
      end

      def view_template
        div(id: ID) do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("members.index.title"),
            subtitle: I18n.t("members.index.subtitle")
          ) do
            if @candidates.any?
              render Components::Ui::Button.new(
                label: I18n.t("members.index.invite"),
                icon: Components::Icons::Plus,
                href: "##{Components::Members::AddForm::ID}"
              )
            end
          end
        end
      end
    end
  end
end
