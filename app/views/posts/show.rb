# frozen_string_literal: true

module Views
  module Posts
    class Show < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(post:)
        @post = post
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Posts",
            title: "Post details",
            subtitle: "Review the post, then make changes or remove it."
          ) do
            if view_context.allowed_to?(:edit?, @post)
              link_to("Edit post", view_context.edit_post_path(@post),
                      class: "ha-button ha-button-secondary")
            end
            if view_context.allowed_to?(:destroy?, @post)
              button_to("Delete", view_context.post_path(@post),
                        method: :delete,
                        class: "ha-button ha-button-danger",
                        form: { class: "inline-flex" },
                        data: { turbo_confirm: "Delete this post?" })
            end
            link_to("Back to posts", view_context.posts_path,
                    class: "ha-button ha-button-secondary")
          end

          render Components::NoticeBanner.new(message: view_context.notice) if view_context.notice.present?

          render Components::PostCard.new(post: @post)
        end
      end
    end
  end
end
