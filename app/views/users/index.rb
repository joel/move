# frozen_string_literal: true

module Views
  module Users
    class Index < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(users:)
        @users = users
      end

      def view_template
        div(class: "w-full") do
          render_notice

          div(class: "flex justify-between items-center") do
            h1(class: "font-bold text-4xl") { "Users" }
            link_to "New user", view_context.new_user_path,
                    class: "rounded-lg py-3 px-5 bg-blue-600 text-white block font-medium"
          end

          div(id: "users", class: "min-w-full") do
            @users.each { |user| render Components::UserCard.new(user: user) }
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
