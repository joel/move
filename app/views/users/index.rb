# frozen_string_literal: true

module Views
  module Users
    class Index < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(users:)
        @users = users
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Directory",
            title: "Users",
            subtitle: "Manage the people connected to your posts."
          ) do
            if view_context.allowed_to?(:new?, User)
              link_to("New user", view_context.new_user_path,
                      class: "ha-button ha-button-primary")
            end
          end

          render Components::NoticeBanner.new(message: view_context.notice) if view_context.notice.present?

          div(id: "users", class: "grid gap-6 md:grid-cols-2") do
            @users.each do |user|
              render Components::UserCard.new(user: user)
            end
          end
        end
      end
    end
  end
end
