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
    class Index < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo

      ROLE_ICONS = {
        "admin" => Components::Icons::Bolt,
        "contributor" => Components::Icons::Pencil,
        "viewer" => Components::Icons::Eye
      }.freeze

      def initialize(move:, memberships:, candidates:, current_user_id:)
        @move = move
        @memberships = memberships
        @candidates = candidates
        @current_user_id = current_user_id
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          role_definitions
          add_member if @candidates.any?
          members
        end
      end

      private

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("members.index.title"),
          subtitle: I18n.t("members.index.subtitle")
        ) do
          if @candidates.any?
            render Components::Ui::Button.new(
              label: I18n.t("members.index.invite"),
              icon: Components::Icons::Plus,
              href: "#add-member"
            )
          end
        end
      end

      # Bento of the three role definitions, with a short explanation of each.
      def role_definitions
        section(
          aria_label: I18n.t("members.index.roles_label"),
          class: "grid grid-cols-1 gap-gutter md:grid-cols-3"
        ) do
          MoveMembership::ROLES.each { |role| role_card(role) }
        end
      end

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

      # Admin-only form to add an existing Organization user to the Move.
      def add_member
        render Components::Ui::Card.new(padding: "p-6", id: "add-member") do
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

      def members
        section(aria_label: I18n.t("members.index.current"), class: "flex flex-col gap-stack-gap") do
          h2(class: "text-headline-md text-text-warm") { I18n.t("members.index.current") }
          @memberships.each { |membership| member_row(membership) }
        end
      end

      def member_row(membership)
        article(
          class: "flex items-center justify-between gap-4 rounded-card border " \
                 "border-card-border bg-card p-4 transition hover:bg-surface-container-high"
        ) do
          identity(membership)
          div(class: "flex items-center gap-3") do
            if own?(membership)
              locked_role(membership)
            else
              role_form(membership)
              remove_button(membership)
            end
          end
        end
      end

      def identity(membership)
        user = membership.user
        div(class: "flex flex-1 items-center gap-4") do
          div(
            class: "flex h-14 w-14 shrink-0 items-center justify-center rounded-full " \
                   "border-2 border-card-border bg-surface-container-high " \
                   "text-headline-md text-on-surface-variant"
          ) { initials(user) }
          div(class: "flex min-w-0 flex-col") do
            span(class: "flex items-center gap-2 text-headline-md text-text-warm") do
              span(class: "truncate") { member_name(user) }
              you_badge if own?(membership)
            end
            span(class: "truncate text-body-md text-on-surface-variant") { user.email }
          end
        end
      end

      def you_badge
        span(
          class: "rounded-full bg-surface-container-high px-2 py-0.5 " \
                 "text-label-caps uppercase text-accent-sage"
        ) { I18n.t("members.you") }
      end

      # The current admin's own role is locked here to avoid self-lockout; the
      # last-admin guard in the actions is the server-side backstop.
      def locked_role(membership)
        div(
          class: "flex items-center gap-2 rounded-full bg-surface-container-high " \
                 "px-4 py-2 text-body-md text-text-warm opacity-70"
        ) { I18n.t("members.roles.#{membership.role}") }
      end

      def role_form(membership)
        form_with(
          url: update_role_move_member_path(@move, membership),
          method: :patch, data: { controller: "auto-submit" }
        ) do
          div(class: "relative") do
            select(
              name: "member[role]",
              data: { action: "change->auto-submit#submit" },
              aria_label: I18n.t("members.actions.change_role", name: member_name(membership.user)),
              class: "cursor-pointer appearance-none rounded-full border border-card-border " \
                     "bg-card py-2 pl-4 pr-9 text-body-md text-text-warm transition " \
                     "hover:border-accent-sage focus:outline-none focus:ring-2 focus:ring-accent-sage/30"
            ) do
              MoveMembership::ROLES.each do |role|
                option(value: role, selected: membership.role == role) do
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

      def remove_button(membership)
        button_to(
          move_member_path(@move, membership),
          method: :delete,
          class: "flex h-10 w-10 items-center justify-center rounded-full " \
                 "text-on-surface-variant transition hover:bg-error/10 hover:text-error",
          form: { data: { turbo_confirm: I18n.t("members.actions.remove_confirm", name: member_name(membership.user)) } },
          aria_label: I18n.t("members.actions.remove", name: member_name(membership.user))
        ) { render Components::Icons::Trash.new(css: "h-5 w-5") }
      end

      def role_options
        MoveMembership::ROLES.map { |role| [I18n.t("members.roles.#{role}"), role] }
      end

      def own?(membership)
        membership.user_id == @current_user_id
      end

      def member_name(user)
        user.name.presence || user.email.to_s.split("@").first
      end

      def candidate_label(user)
        user.name.present? ? "#{user.name} · #{user.email}" : user.email
      end

      def initials(user)
        source = user.name.presence || user.email.to_s
        letters = source.scan(/[[:alnum:]]+/).first(2).pluck(0).join
        letters.presence&.upcase || "?"
      end
    end
  end
end
