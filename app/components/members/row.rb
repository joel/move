# frozen_string_literal: true

module Components
  module Members
    # F1 — one member of a Move: avatar + identity, and (for everyone but the
    # current admin's own locked row) an inline role select that auto-submits and
    # a remove button. Carries a stable per-membership DOM id so the controller can
    # stream a removal or a reverted role change without reloading the roster.
    class Row < Components::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(membership)
        "member-#{membership.id}"
      end

      #: (move: untyped, membership: untyped, current_user_id: untyped, ?highlight: untyped) -> void
      def initialize(move:, membership:, current_user_id:, highlight: false)
        @move = move
        @membership = membership
        @current_user_id = current_user_id
        @highlight = highlight
      end

      #: () -> void
      def view_template
        article(
          id: self.class.dom_id(@membership), data: row_data,
          # Stack on a phone (the role control drops below the identity) and go
          # side-by-side at sm+ — otherwise the role pill/select overflows the
          # card on narrow screens. Mirrors Members::PendingRow.
          class: "flex flex-col gap-3 rounded-card border border-card-border bg-card p-4 " \
                 "transition hover:bg-surface-container-high " \
                 "sm:flex-row sm:items-center sm:justify-between"
        ) do
          identity
          # pl-[4.5rem] on mobile lines the control up under the name, clearing
          # the 3.5rem avatar + 1rem gap; reset at sm where the row is horizontal.
          div(class: "flex shrink-0 items-center gap-3 pl-[4.5rem] sm:pl-0") do
            if own?
              locked_role
            else
              role_form
              remove_button
            end
          end
        end
      end

      private

      #: () -> untyped
      def row_data
        @highlight ? { controller: "highlight" } : {}
      end

      #: () -> untyped
      def identity
        user = @membership.user
        div(class: "flex flex-1 items-center gap-4") do
          div(
            class: "flex h-14 w-14 shrink-0 items-center justify-center rounded-full " \
                   "border-2 border-card-border bg-surface-container-high " \
                   "text-headline-md text-on-surface-variant"
          ) { initials(user) }
          div(class: "flex min-w-0 flex-col") do
            span(class: "flex items-center gap-2 text-headline-md text-text-warm") do
              span(class: "truncate") { member_name(user) }
              you_badge if own?
            end
            span(class: "truncate text-body-md text-on-surface-variant") { user.email }
          end
        end
      end

      #: () -> untyped
      def you_badge
        span(
          class: "rounded-full bg-surface-container-high px-2 py-0.5 " \
                 "text-label-caps uppercase text-accent-sage"
        ) { I18n.t("members.you") }
      end

      # The current admin's own role is locked here to avoid self-lockout; the
      # last-admin guard in the actions is the server-side backstop.

      #: () -> untyped
      def locked_role
        div(
          class: "flex items-center gap-2 rounded-full bg-surface-container-high " \
                 "px-4 py-2 text-body-md text-text-warm opacity-70"
        ) { I18n.t("members.roles.#{@membership.role}") }
      end

      #: () -> untyped
      def role_form
        form_with(
          url: update_role_move_member_path(@move, @membership),
          method: :patch, data: { controller: "auto-submit" }
        ) do
          div(class: "relative") do
            select(
              name: "member[role]",
              data: { action: "change->auto-submit#submit" },
              aria_label: I18n.t("members.actions.change_role", name: member_name(@membership.user)),
              class: "cursor-pointer appearance-none rounded-full border border-card-border " \
                     "bg-card py-2 pl-4 pr-9 text-body-md text-text-warm transition " \
                     "hover:border-accent-sage focus:outline-none focus:ring-2 focus:ring-accent-sage/30"
            ) do
              MoveMembership::ROLES.each do |role|
                option(value: role, selected: @membership.role == role) do
                  I18n.t("members.roles.#{role}")
                end
              end
            end
            span(
              class: "pointer-events-none absolute inset-y-0 right-3 flex items-center " \
                     "text-on-surface-variant"
            ) { render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-90") }
          end
        end
      end

      #: () -> untyped
      def remove_button
        button_to(
          move_member_path(@move, @membership),
          method: :delete,
          class: "flex h-10 w-10 items-center justify-center rounded-full " \
                 "text-on-surface-variant transition hover:bg-error/10 hover:text-error",
          form: { data: { turbo_confirm: I18n.t("members.actions.remove_confirm", name: member_name(@membership.user)) } },
          aria_label: I18n.t("members.actions.remove", name: member_name(@membership.user))
        ) { render Components::Icons::Trash.new(css: "h-5 w-5") }
      end

      #: () -> untyped
      def own?
        @membership.user_id == @current_user_id
      end

      #: (untyped user) -> untyped
      def member_name(user)
        user.name.presence || user.email.to_s.split("@").first
      end

      #: (untyped user) -> untyped
      def initials(user)
        source = user.name.presence || user.email.to_s
        letters = source.scan(/[[:alnum:]]+/).first(2).pluck(0).join
        letters.presence&.upcase || "?"
      end
    end
  end
end
