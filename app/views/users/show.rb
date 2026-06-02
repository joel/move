# frozen_string_literal: true

module Views
  module Users
    class Show < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(user:)
        @user = user
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Users",
            title: "User details",
            subtitle: "Review details before updating or removing."
          ) do
            render_actions
          end

          render Components::NoticeBanner.new(message: view_context.notice) if view_context.notice.present?

          render Components::UserCard.new(user: @user)
        end
      end

      private

      def render_actions
        if view_context.allowed_to?(:edit?, @user)
          link_to("Edit user", view_context.edit_user_path(@user),
                  class: "ha-button ha-button-secondary")
        end
        if view_context.allowed_to?(:destroy?, @user)
          button_to("Delete", view_context.user_path(@user),
                    method: :delete,
                    class: "ha-button ha-button-danger",
                    form: { class: "inline-flex" })
        end
        link_to("Back to users", view_context.users_path,
                class: "ha-button ha-button-secondary")
      end
    end
  end
end
