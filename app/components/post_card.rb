# frozen_string_literal: true

module Components
  class PostCard < Components::Base
    include Phlex::Rails::Helpers::LinkTo
    include Phlex::Rails::Helpers::DOMID

    def initialize(post:)
      @post = post
    end

    def view_template
      div(id: dom_id(@post), class: "ha-card p-6") do
        div(class: "flex flex-wrap items-start justify-between gap-4") do
          div do
            p(class: "ha-overline") { "Post" }
            h3(class: "mt-2 text-lg font-semibold text-[var(--ha-text)]") do
              plain @post.title
            end
          end
        end

        if @post.body.present?
          p(class: "mt-4 text-sm leading-relaxed text-[var(--ha-text)] opacity-80") do
            plain @post.body
          end
        end

        div(class: "mt-4 flex items-center gap-2 text-xs text-[var(--ha-muted)]") do
          span(class: "rounded-full bg-[var(--ha-surface-high)] px-2 py-1") { "Author" }
          span(class: "font-semibold text-[var(--ha-text)]") do
            plain(@post.user&.name.presence || @post.user&.email)
          end
        end

        render_actions unless view_context.action_name == "show"
      end
    end

    private

    def render_actions
      div(class: "mt-5 flex flex-wrap gap-3") do
        link_to(
          "View", @post,
          class: "text-sm font-semibold text-[var(--ha-primary)] hover:underline"
        )
        if view_context.allowed_to?(:edit?, @post)
          link_to(
            "Edit", view_context.edit_post_path(@post),
            class: "text-sm font-medium text-[var(--ha-on-surface-variant)] " \
                   "hover:text-[var(--ha-primary)]"
          )
        end
      end
    end
  end
end
