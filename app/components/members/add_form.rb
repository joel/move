# frozen_string_literal: true

module Components
  module Members
    # F1 — the "add an existing Organization member" card. Stable id so the
    # controller can refresh it whenever the candidate pool changes (a user added
    # leaves the pool; a user removed rejoins it) and hide it when no candidates
    # remain. Always renders the container so the stream always has a target and
    # the header "Invite" anchor (#add-member) keeps working.
    class AddForm < Components::Base
      include Phlex::Rails::Helpers::FormWith

      ID = "add-member"

      #: (move: untyped, candidates: untyped) -> void
      def initialize(move:, candidates:)
        @move = move
        @candidates = candidates.to_a
      end

      #: () -> void
      def view_template
        div(id: ID) do
          card if @candidates.any?
        end
      end

      private

      #: () -> untyped
      def card
        render Components::Ui::Card.new(padding: "p-6") do
          h3(class: "text-headline-md text-text-warm") { I18n.t("members.add.title") }
          form_with(url: move_members_path(@move), method: :post) do
            div(class: "flex flex-col gap-4 sm:flex-row sm:items-end") do
              div(class: "flex-1") do
                render Components::Ui::Select.new(
                  name: "member[user_id]",
                  label: I18n.t("members.add.user"),
                  options: @candidates.map { |user| [candidate_label(user), user.id] }
                )
              end
              div(class: "sm:w-48") do
                render Components::Ui::Select.new(
                  name: "member[role]",
                  label: I18n.t("members.add.role"),
                  options: role_options,
                  selected: "contributor"
                )
              end
              render Components::Ui::Button.new(label: I18n.t("members.add.submit"), type: "submit")
            end
          end
        end
      end

      #: () -> untyped
      def role_options
        MoveMembership::ROLES.map { |role| [I18n.t("members.roles.#{role}"), role] }
      end

      #: (untyped user) -> untyped
      def candidate_label(user)
        user.name.present? ? "#{user.name} · #{user.email}" : user.email
      end
    end
  end
end
