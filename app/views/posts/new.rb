# frozen_string_literal: true

module Views
  module Posts
    class New < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(post:)
        @post = post
      end

      def view_template
        div(class: "space-y-6") do
          render Components::PageHeader.new(
            section: "Posts",
            title: "New post",
            subtitle: "Draft a new update."
          )

          div(class: "ha-card p-6") do
            render Components::PostForm.new(post: @post)
          end

          div(class: "flex flex-wrap gap-2") do
            link_to("Back to posts", view_context.posts_path,
                    class: "ha-button ha-button-secondary")
          end
        end
      end
    end
  end
end
