# frozen_string_literal: true

module Components
  class AccountForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    def initialize(user:)
      @user = user
    end

    def view_template
      form_with(model: @user, url: view_context.account_path, class: "space-y-6") do |form|
        render_errors if @user.errors.any?

        div do
          form.label :name, class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          form.text_field :name, class: "ha-input mt-2"
        end

        div(class: "flex flex-wrap gap-2") do
          form.submit "Save changes", class: "ha-button ha-button-primary"
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
          plain "#{pluralize(@user.errors.count, "error")} prohibited this account from being saved:"
        end
        ul(class: "mt-2 list-disc space-y-1 pl-5") do
          @user.errors.each do |error|
            li { error.full_message }
          end
        end
      end
    end
  end
end
