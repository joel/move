# frozen_string_literal: true

module Views
  module Users
    class New < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(user:)
        @user = user
      end

      def view_template
        div(class: "space-y-6") do
          render Components::PageHeader.new(
            section: "Users",
            title: "New user",
            subtitle: "Add someone who can own posts."
          )

          div(class: "ha-card p-6") do
            render Components::UserForm.new(user: @user)
          end

          div(class: "flex flex-wrap gap-2") do
            link_to("Back to users", view_context.users_path,
                    class: "ha-button ha-button-secondary")
          end
        end
      end
    end
  end
end
