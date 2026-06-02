# frozen_string_literal: true

module Views
  module Accounts
    class Show < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(user:)
        @user = user
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Account",
            title: "My account",
            subtitle: "Keep your profile details up to date."
          ) do
            link_to("Edit account", view_context.edit_account_path,
                    class: "ha-button ha-button-secondary")
            button_to("Sign out", view_context.rodauth.logout_path,
                      method: :post,
                      form: { class: "inline-flex" },
                      class: "ha-button ha-button-secondary")
            button_to("Delete account", view_context.account_path,
                      method: :delete,
                      class: "ha-button ha-button-danger",
                      form: { class: "inline-flex" },
                      data: { turbo_confirm: "Delete your account permanently?" })
          end

          render Components::NoticeBanner.new(message: view_context.notice) if view_context.notice.present?

          render Components::AccountDetails.new(user: @user)
        end
      end
    end
  end
end
