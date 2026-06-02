# frozen_string_literal: true

module Views
  module Posts
    class Index < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(posts:)
        @posts = posts
      end

      def view_template
        div(class: "w-full") do
          render_notice

          div(class: "flex justify-between items-center") do
            h1(class: "font-bold text-4xl") { "Posts" }
            link_to "New post", view_context.new_post_path,
                    class: "rounded-lg py-3 px-5 bg-blue-600 text-white block font-medium"
          end

          div(id: "posts", class: "min-w-full") do
            @posts.each { |post| render Components::PostCard.new(post: post) }
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
