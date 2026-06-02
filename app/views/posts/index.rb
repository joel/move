# frozen_string_literal: true

module Views
  module Posts
    class Index < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(posts:)
        @posts = posts
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Content",
            title: "Posts",
            subtitle: "Keep updates organized and visible for the whole team."
          ) do
            if view_context.allowed_to?(:new?, Post)
              link_to("New post", view_context.new_post_path,
                      class: "ha-button ha-button-primary")
            end
          end

          render Components::NoticeBanner.new(message: view_context.notice) if view_context.notice.present?

          div(id: "posts", class: "grid gap-4") do
            @posts.each { |post| render Components::PostCard.new(post: post) }
          end
        end
      end
    end
  end
end
