# frozen_string_literal: true

module Views
  module Onboarding
    # Create the first Organization. Styled with the D1/D0 design system (there
    # is no dedicated Stitch screen for onboarding — it is part of the shell).
    class New < Views::Base
      include Phlex::Rails::Helpers::FormWith

      def initialize(organization:)
        @organization = organization
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-md flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: t("onboarding.eyebrow"),
            title: t("onboarding.title"),
            subtitle: t("onboarding.subtitle")
          )
          render Components::Ui::Card.new(padding: "p-6") do
            render_form
          end
        end
      end

      private

      def render_form
        # Turbo can't follow the cross-host redirect to the new org subdomain,
        # so submit this form as a standard (non-Turbo) request.
        form_with(
          model: @organization, url: view_context.onboarding_path,
          class: "flex flex-col gap-stack-gap", data: { turbo: false }
        ) do |form|
          render_errors if @organization.errors.any?
          render Components::Ui::Field.new(
            name: "organization[name]", label: t("onboarding.fields.name"),
            value: @organization.name,
            placeholder: t("onboarding.fields.name_placeholder"), required: true
          )
          render Components::Ui::Field.new(
            name: "organization[slug]", label: t("onboarding.fields.slug"),
            value: @organization.slug,
            placeholder: t("onboarding.fields.slug_placeholder"),
            hint: t("onboarding.fields.slug_hint", host: Rails.configuration.x.tenant_domain),
            required: true
          )
          div(class: "mt-2") do
            form.submit t("onboarding.submit"), class: "ha-button ha-button-primary w-full"
          end
        end
      end

      def render_errors
        div(class: "rounded-card border border-error/40 bg-error-container/30 px-4 py-3 " \
                   "text-body-md text-error") do
          ul(class: "list-disc space-y-1 pl-5") do
            @organization.errors.full_messages.each { |message| li { message } }
          end
        end
      end
    end
  end
end
