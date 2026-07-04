# frozen_string_literal: true

module Components
  # Profile panel: avatar, name (rename inline via the pencil), email, role chip.
  class AccountDetails < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    #: (user: untyped) -> void
    def initialize(user:)
      @user = user
    end

    #: () -> void
    def view_template
      div(
        class: "ha-card p-8",
        # The string "true" (not a Ruby boolean): Phlex renders `true` as a bare
        # `data-inline-edit-open-value` attribute, which Stimulus reads as false (a
        # Boolean value coerces via `=== "true"`), so a rejected save wouldn't
        # reopen the form to show the error. `false` is dropped by Phlex (Stimulus
        # then defaults to false). Mirrors Components::Vocabularies::Row (#383).
        data: { controller: "inline-edit", inline_edit_open_value: (@user.errors.any? ? "true" : false) }
      ) do
        div(class: "flex items-center gap-6") do
          render_avatar
          div(class: "min-w-0 flex-1") do
            render_name_display
            render_name_form
            p(class: "mt-1 text-sm text-[var(--ha-on-surface-variant)]") { plain @user.email }
            render_role_chip
          end
        end
      end
    end

    private

    #: () -> untyped
    def render_name_display
      div(
        class: "flex items-center gap-2",
        data: { inline_edit_target: "display" }
      ) do
        h2(class: "truncate font-headline text-2xl font-bold") do
          plain(@user.name.presence || "Unnamed")
        end
        button(
          type: "button",
          aria: { label: "Edit name" },
          data: { action: "inline-edit#edit" },
          class: "flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full " \
                 "text-[var(--ha-muted)] transition hover:bg-[var(--ha-surface-high)] " \
                 "hover:text-[var(--ha-text)]"
        ) { render Components::Icons::Pencil.new(css: "h-4 w-4") }
      end
    end

    #: () -> untyped
    def render_name_form
      div(class: "hidden", data: { inline_edit_target: "form" }) do
        form_with(model: @user, url: view_context.account_path, class: "space-y-3") do |form|
          render_errors if @user.errors.any?
          div(class: "flex items-center gap-2") do
            form.text_field(
              :name,
              class: "ha-input flex-1",
              aria: { label: "Account name" },
              data: { inline_edit_target: "input" }
            )
            form.submit("Save", class: "ha-button ha-button-primary !px-4 !py-2 text-sm")
            button(
              type: "button",
              data: { action: "inline-edit#cancel" },
              class: "ha-button ha-button-secondary !px-4 !py-2 text-sm"
            ) { plain "Cancel" }
          end
        end
      end
    end

    #: () -> untyped
    def render_errors
      div(
        id: "error_explanation",
        class: "rounded-2xl bg-[var(--ha-error-container)] px-4 py-3 text-sm text-[var(--ha-error)]"
      ) do
        ul(class: "list-disc space-y-1 pl-5") do
          @user.errors.each { |error| li { error.full_message } }
        end
      end
    end

    #: () -> untyped
    def render_avatar
      div(class: "flex h-20 w-20 flex-shrink-0 items-center " \
                 "justify-center rounded-full " \
                 "bg-[var(--ha-primary-container)]/20 " \
                 "text-2xl font-bold " \
                 "text-[var(--ha-primary)]") do
        plain user_initials
      end
    end

    #: () -> untyped
    def render_role_chip
      div(class: "mt-3") do
        span(class: "inline-flex rounded-full px-3 py-1 " \
                    "text-[10px] font-bold uppercase tracking-widest " \
                    "bg-[var(--ha-surface-high)] " \
                    "text-[var(--ha-on-surface-variant)]") do
          plain role_label
        end
      end
    end

    #: () -> untyped
    def user_initials
      name = @user.name.presence
      if name
        name.split.pluck(0).first(2).join.upcase
      else
        @user.email.first.upcase
      end
    end

    #: () -> untyped
    def role_label
      if @user.role?(:admin) then "Admin"
      elsif @user.role?(:contributor) then "Contributor"
      elsif @user.role?(:viewer) then "Viewer"
      else "No role"
      end
    end
  end
end
