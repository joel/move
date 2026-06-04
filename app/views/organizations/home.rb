# frozen_string_literal: true

module Views
  module Organizations
    # Tenant root placeholder (PR1). PR2 replaces this with the A1 Move selector
    # (list / empty state / create form).
    class Home < Views::Base
      def initialize(organization:)
        @organization = organization
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-2xl flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: t("organizations.home.eyebrow"),
            title: @organization.name,
            subtitle: t("organizations.home.subtitle")
          )
          render Components::Ui::EmptyState.new(
            title: t("organizations.home.empty_title"),
            description: t("organizations.home.empty_description")
          )
        end
      end
    end
  end
end
