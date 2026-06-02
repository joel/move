# frozen_string_literal: true

# Phlex replacement for the scaffold-generated `users/_form.html.erb` partial.
module Components
  class UserForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    INPUT_CLASS =
      "block shadow rounded-md border border-gray-200 outline-none px-3 py-2 mt-2 w-full"

    def initialize(user:)
      @user = user
    end

    def view_template
      form_with(model: @user, class: "contents") do |form|
        render_errors if @user.errors.any?

        div(class: "my-5") do
          form.label :name
          form.text_field :name, class: INPUT_CLASS
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
          plain "#{pluralize(@user.errors.count, "error")} " \
                "prohibited this user from being saved:"
        end
        ul do
          @user.errors.each { |error| li { error.full_message } }
        end
      end
    end
  end
end
