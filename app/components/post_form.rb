# frozen_string_literal: true

# Phlex replacement for the scaffold-generated `posts/_form.html.erb` partial.
# The `user_id` field is a <select> populated from User.all (matching the
# ERB template's `post_form.erb.patch`).
module Components
  class PostForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    INPUT_CLASS =
      "block shadow rounded-md border border-gray-200 outline-none px-3 py-2 mt-2 w-full"

    def initialize(post:)
      @post = post
    end

    def view_template
      form_with(model: @post, class: "contents") do |form|
        render_errors if @post.errors.any?

        div(class: "my-5") do
          form.label :title
          form.text_field :title, class: INPUT_CLASS
        end

        div(class: "my-5") do
          form.label :body
          form.text_area :body, rows: 4, class: INPUT_CLASS
        end

        div(class: "my-5") do
          form.label :user_id
          form.select :user_id,
                      User.all.collect { |u| [u.name, u.id] },
                      { include_blank: false },
                      { class: INPUT_CLASS }
        end

        div(class: "inline") do
          form.submit class: "rounded-lg py-3 px-5 bg-blue-600 text-white " \
                             "inline-block font-medium cursor-pointer"
        end
      end
    end

    private

    def render_errors
      div(
        id: "error_explanation",
        class: "bg-red-50 text-red-500 px-3 py-2 font-medium rounded-lg mt-3"
      ) do
        h2 do
          plain "#{pluralize(@post.errors.count, "error")} " \
                "prohibited this post from being saved:"
        end
        ul do
          @post.errors.each { |error| li { error.full_message } }
        end
      end
    end
  end
end
