# frozen_string_literal: true

module Views
  module Settings
    # F3 / #242 — shared "AI Capability" keys. One row per vendor (OpenAI,
    # Anthropic, Gemini, Voyage): a masked status, a write-only password field to
    # add/replace the key (Moves::SetProviderKey), a Remove action when set
    # (Moves::RemoveProviderKey), and badges for the features that vendor powers.
    # Admin-only (the caller gates rendering); keys are never shown in full — only
    # "••••" + last 4. Enter a key here once; the Recognition and Semantic Search
    # selectors below light up their keyed options.
    class AiCapabilityPanel < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      def initialize(move:)
        @move = move
      end

      def view_template
        div(class: "flex flex-col gap-2") do
          span(class: "text-body-md text-on-surface-variant") { t("subtitle") }
          div(class: "mt-2 flex flex-col divide-y divide-card-border") do
            Move::PROVIDER_KEYS.each { |provider| provider_row(provider) }
          end
        end
      end

      private

      def provider_row(provider)
        div(class: "flex flex-col gap-3 py-4 first:pt-2") do
          div(class: "flex items-center justify-between gap-4") do
            div(class: "flex flex-col gap-1") do
              span(class: "text-headline-md text-text-warm") { t("providers.#{provider}") }
              powers(provider)
            end
            status_chip(provider)
          end
          key_form(provider)
          remove_button(provider) if @move.api_key_for(provider).present?
        end
      end

      def powers(provider)
        div(class: "flex flex-wrap gap-1.5") do
          @move.provider_powers(provider).each do |feature|
            span(class: "rounded-full bg-surface-container-high px-2.5 py-0.5 " \
                        "text-label-caps uppercase text-on-surface-variant") { t("powers.#{feature}") }
          end
        end
      end

      def status_chip(provider)
        if @move.api_key_for(provider).present?
          span(class: "rounded-full bg-accent-sage/20 px-3 py-1 font-mono text-label-caps text-accent-sage") do
            "#{t("status_set")} #{masked_key(provider)}"
          end
        else
          span(class: "rounded-full bg-surface-container-high px-3 py-1 text-label-caps " \
                      "uppercase text-on-surface-variant") { t("status_unset") }
        end
      end

      def key_form(provider)
        form_with(url: move_settings_provider_key_path(@move), method: :patch,
                  class: "flex flex-col gap-2 sm:flex-row sm:items-end") do
          input(type: "hidden", name: "move[provider]", value: provider)
          div(class: "flex-1") do
            render Components::Ui::Field.new(
              name: "move[api_key]", type: "password",
              label: t("providers.#{provider}"),
              placeholder: t("api_key_placeholder", provider: t("providers.#{provider}")),
              autocomplete: "off"
            )
          end
          render Components::Ui::Button.new(label: t("save"), type: "submit", variant: :secondary)
        end
      end

      def remove_button(provider)
        button_to(
          t("remove"), move_settings_remove_provider_key_path(@move, provider: provider),
          method: :delete,
          class: "self-start text-label-caps uppercase text-secondary transition hover:underline"
        )
      end

      # "••••" + last 4 of the stored key. Admin-only surface; never the full key.
      def masked_key(provider)
        key = @move.api_key_for(provider)
        key.present? ? "••••#{key[-4..]}" : ""
      end

      def t(key, **)
        I18n.t("settings.show.ai_capability.#{key}", **)
      end
    end
  end
end
