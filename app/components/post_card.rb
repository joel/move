# frozen_string_literal: true

# Phlex replacement for the scaffold-generated `posts/_post.html.erb` partial.
module Components
  class PostCard < Components::Base
    include Phlex::Rails::Helpers::LinkTo
    include Phlex::Rails::Helpers::DOMID

    def initialize(post:)
      @post = post
    end

    def view_template
      div(id: dom_id(@post), class: "post-card") do
        p(class: "my-5") do
          strong(class: "block font-medium mb-1") { "Title:" }
          plain @post.title
        end

        p(class: "my-5") do
          strong(class: "block font-medium mb-1") { "Body:" }
          plain @post.body
        end

        p(class: "my-5") do
          strong(class: "block font-medium mb-1") { "User:" }
          plain @post.user.name
        end

        render_actions unless view_context.action_name == "show"
      end
    end

    private

    def render_actions
      link_to "Show this post", @post,
              class: "rounded-lg py-3 px-5 bg-gray-100 inline-block font-medium"
      link_to "Edit this post", view_context.edit_post_path(@post),
              class: "rounded-lg py-3 ms-2 px-5 bg-gray-100 inline-block font-medium"
    end
  end
end
