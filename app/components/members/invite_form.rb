# frozen_string_literal: true

module Components
  module Members
    # F1/D14 — invite anyone by email (#608). Unlike the AddForm (existing
    # Organization users only, pool-gated), this card always renders: it is the
    # header CTA's anchor and the answer to "no spare org users = no way to
    # invite". After a streamed success the reset-form controller clears the
    # email and refocuses it for rapid multi-invite; a failure keeps the input.
    class InviteForm < Components::Base
      include Phlex::Rails::Helpers::FormWith

      ID = "invite-member"

      #: (move: untyped) -> void
      def initialize(move:)
        @move = move
      end

      #: () -> void
      def view_template
        div(id: ID) do
          render Components::Ui::Card.new(padding: "p-6") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("members.invite_form.title") }
            p(class: "text-body-md text-on-surface-variant") do
              I18n.t("members.invite_form.subtitle")
            end
            invite_form
          end
        end
      end

      private

      #: () -> untyped
      def invite_form
        form_with(
          url: move_invitations_path(@move), method: :post,
          data: { controller: "reset-form", action: "turbo:submit-end->reset-form#reset" }
        ) do |_form|
          div(class: "flex flex-col gap-4 sm:flex-row sm:items-end") do
            div(class: "flex-1") do
              render Components::Ui::Field.new(
                name: "invitation[email]", type: "email",
                label: I18n.t("members.invite_form.email"),
                placeholder: I18n.t("members.invite_form.email_placeholder"),
                required: true
              )
            end
            div(class: "sm:w-48") do
              render Components::Ui::Select.new(
                name: "invitation[role]",
                label: I18n.t("members.invite_form.role"),
                options: role_options,
                selected: "contributor"
              )
            end
            render Components::Ui::Button.new(label: I18n.t("members.invite_form.submit"), type: "submit")
          end
        end
      end

      #: () -> untyped
      def role_options
        MoveMembership::ROLES.map { |role| [I18n.t("members.roles.#{role}"), role] }
      end
    end
  end
end
