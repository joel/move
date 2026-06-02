# frozen_string_literal: true

module Components
  class UserForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    def initialize(user:)
      @user = user
    end

    def view_template
      form_with(model: @user, class: "space-y-6") do |form|
        render_errors if @user.errors.any?

        div do
          form.label :name, class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          form.text_field :name, class: "ha-input mt-2"
        end

        div do
          form.label :email, class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          form.email_field :email, class: "ha-input mt-2", autocomplete: "email"
        end

        render_roles(form)

        div(class: "flex flex-wrap gap-2") do
          form.submit class: "ha-button ha-button-primary"
        end
      end
    end

    private

    def render_errors
      div(
        id: "error_explanation",
        class: "rounded-2xl bg-[var(--ha-error-container)] px-5 py-4 text-sm text-[var(--ha-error)]"
      ) do
        h2(class: "font-semibold") do
          plain "#{pluralize(@user.errors.count, "error")} prohibited this user from being saved:"
        end
        ul(class: "mt-2 list-disc space-y-1 pl-5") do
          @user.errors.each do |error|
            li { error.full_message }
          end
        end
      end
    end

    def render_roles(form)
      div do
        span(class: "text-sm font-medium text-[var(--ha-on-surface-variant)]") { "Roles" }
        div(class: "mt-3 grid gap-2 sm:grid-cols-2") do
          form.collection_check_boxes(:roles, User.roles_config, :to_s, :to_s) do |box|
            label(
              class: "flex items-center gap-2 rounded-xl border border-[var(--ha-border)] " \
                     "bg-[var(--ha-surface)] px-3 py-2 text-sm text-[var(--ha-text)]"
            ) do
              box.check_box(
                class: "h-4 w-4 rounded border-[var(--ha-border)] text-[var(--ha-accent)] " \
                       "focus:ring-2 focus:ring-[var(--ha-accent)]"
              )
              span(class: "capitalize") { box.text.tr("_", " ") }
            end
          end
        end
      end
    end
  end
end
