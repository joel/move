# frozen_string_literal: true

# Phlex replacement for the scaffold-generated `users/_user.html.erb` partial.
module Components
  class UserCard < Components::Base
    include Phlex::Rails::Helpers::LinkTo
    include Phlex::Rails::Helpers::DOMID

    def initialize(user:)
      @user = user
    end

    def view_template
      div(id: dom_id(@user)) do
        p(class: "my-5") do
          strong(class: "block font-medium mb-1") { "Name:" }
          plain @user.name
        end

        render_actions unless view_context.action_name == "show"
      end
    end

    private

    def render_actions
      link_to "Show this user", @user,
              class: "rounded-lg py-3 px-5 bg-gray-100 inline-block font-medium"
      link_to "Edit this user", view_context.edit_user_path(@user),
              class: "rounded-lg py-3 ms-2 px-5 bg-gray-100 inline-block font-medium"
    end
  end
end
