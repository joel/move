# frozen_string_literal: true

module Views
  module Users
    class Edit < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(user:)
        @user = user
      end

      def view_template
        div(class: "mx-auto md:w-2/3 w-full") do
          h1(class: "font-bold text-4xl") { "Editing user" }

          render Components::UserForm.new(user: @user)

          link_to "Show this user", @user,
                  class: "ml-2 rounded-lg py-3 px-5 bg-gray-100 inline-block font-medium"
          link_to "Back to users", view_context.users_path,
                  class: "ml-2 rounded-lg py-3 px-5 bg-gray-100 inline-block font-medium"
        end
      end
    end
  end
end
