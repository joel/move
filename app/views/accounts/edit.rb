# frozen_string_literal: true

module Views
  module Accounts
    class Edit < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(user:)
        @user = user
      end

      def view_template
        div(class: "space-y-6") do
          render Components::PageHeader.new(
            section: "Account",
            title: "Edit account",
            subtitle: "Update your name."
          )

          div(class: "ha-card p-6") do
            render Components::AccountForm.new(user: @user)
          end

          div(class: "flex flex-wrap gap-2") do
            link_to("Back to account", view_context.account_path,
                    class: "ha-button ha-button-secondary")
          end
        end
      end
    end
  end
end
