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
        div(class: "mx-auto md:w-2/3 w-full flex") do
          div(class: "mx-auto") do
            render_notice

            render Components::PostCard.new(post: @post)

            link_to "Edit this post", view_context.edit_post_path(@post),
                    class: "mt-2 rounded-lg py-3 px-5 bg-gray-100 inline-block font-medium"
            div(class: "inline-block ms-2") do
              button_to "Destroy this post", @post, method: :delete,
                                                    class: "mt-2 rounded-lg py-3 px-5 bg-gray-100 font-medium"
            end
            link_to "Back to posts", view_context.posts_path,
                    class: "ms-2 rounded-lg py-3 px-5 bg-gray-100 inline-block font-medium"
          end
        end
      end

      private

      def render_notice
        return if view_context.notice.blank?

        p(
          id: "notice",
          class: "py-2 px-3 bg-green-50 mb-5 text-green-500 font-medium rounded-lg inline-block"
        ) { view_context.notice }
      end
    end
  end
end
