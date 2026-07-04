# frozen_string_literal: true

module Views
  module Members
    # F1 — Members & Roles (admin-only). A header with an invite action, a
    # bento of role definitions (admin/contributor/viewer), and the current
    # member list with inline role changes and removal. Built against the Stitch
    # "Members & Roles (Dark) - Responsive" screen, rendered from project tokens
    # (Stitch is dark-only). New-user email invitations are deferred, so there is
    # no pending-invite row — members are existing Organization users added
    # immediately.
    #
    # The add form, list and rows are extracted into stable-id Components so the
    # controller can stream add/role-change/remove without a reload (#385).
    class Index < Views::Base
      ROLE_ICONS = {
        "admin" => Components::Icons::Bolt,
        "contributor" => Components::Icons::Pencil,
        "viewer" => Components::Icons::Eye
      }.freeze

      #: (move: untyped, memberships: untyped, candidates: untyped, current_user_id: untyped) -> void
      def initialize(move:, memberships:, candidates:, current_user_id:)
        @move = move
        @memberships = memberships
        @candidates = candidates
        @current_user_id = current_user_id
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Members::Header.new(move: @move, candidates: @candidates)
          role_definitions
          render Components::Members::AddForm.new(move: @move, candidates: @candidates)
          render Components::Members::List.new(
            move: @move, memberships: @memberships, current_user_id: @current_user_id
          )
        end
      end

      private

      # Bento of the three role definitions, with a short explanation of each.

      #: () -> untyped
      def role_definitions
        section(
          aria_label: I18n.t("members.index.roles_label"),
          class: "grid grid-cols-1 gap-gutter md:grid-cols-3"
        ) do
          MoveMembership::ROLES.each { |role| role_card(role) }
        end
      end

      #: (untyped role) -> untyped
      def role_card(role)
        render Components::Ui::Card.new(padding: "p-6") do
          div(class: "flex items-center gap-3") do
            div(
              class: "flex h-8 w-8 items-center justify-center rounded-full " \
                     "bg-surface-container-high text-accent-sage"
            ) do
              render ROLE_ICONS.fetch(role).new(css: "h-[18px] w-[18px]")
            end
            h3(class: "text-headline-md text-text-warm") { I18n.t("members.roles.#{role}") }
          end
          p(class: "text-body-md leading-relaxed text-on-surface-variant") do
            I18n.t("members.role_descriptions.#{role}")
          end
        end
      end
    end
  end
end
