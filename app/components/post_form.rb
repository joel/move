# frozen_string_literal: true

module Components
  class PostForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    def initialize(post:)
      @post = post
    end

    def view_template
      form_with(model: @post, class: "space-y-6") do |form|
        render_errors if @post.errors.any?

        div do
          form.label :title, class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          form.text_field :title, class: "ha-input mt-2"
        end

        div do
          form.label :body, class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          form.text_area :body, rows: 6, class: "ha-input mt-2"
        end

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
          plain "#{pluralize(@post.errors.count, "error")} prohibited this post from being saved:"
        end
        ul(class: "mt-2 list-disc space-y-1 pl-5") do
          @post.errors.each do |error|
            li { error.full_message }
          end
        end
      end
    end
  end
end
