# frozen_string_literal: true

module Views
  module Settings
    # F3 — Settings & Assistant. Appearance (client-side dark-mode switch), Move
    # preferences (measurement units, auto-confirm confidence), the Assistant &
    # Integrations panel (MCP tokens), and account actions. Built against the
    # Stitch "Settings & Assistant" screens, rendered from project tokens.
    #
    # Editors see interactive unit/threshold controls; viewers and archived Moves
    # see resolved values read-only. The token panel is admin-only and reveals a
    # freshly-created raw token exactly once (`revealed_token`).
    class Show < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      def initialize(move:, tokens:, editable:, manage_tokens:, revealed_token: nil)
        @move = move
        @tokens = tokens
        @editable = editable
        @manage_tokens = manage_tokens
        @revealed_token = revealed_token
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("settings.show.title"),
            subtitle: I18n.t("settings.show.subtitle")
          )
          read_only_note unless @editable
          appearance_section
          preferences_section
          recognition_section
          assistant_section
          account_section
        end
      end

      private

      def read_only_note
        p(class: "rounded-card border border-card-border bg-surface-container-high px-4 py-3 " \
                 "text-body-md text-on-surface-variant") { I18n.t("settings.show.read_only_note") }
      end

      # --- Appearance: client-only dark-mode switch (theme Stimulus controller) ---
      def appearance_section
        setting_card(I18n.t("settings.show.appearance.title")) do
          div(class: "flex items-center justify-between gap-4") do
            div(class: "flex flex-col gap-1") do
              span(class: "text-headline-md text-text-warm") { I18n.t("settings.show.appearance.dark_mode") }
              span(class: "text-body-md text-on-surface-variant") do
                I18n.t("settings.show.appearance.dark_mode_caption")
              end
            end
            theme_switch
          end
        end
      end

      def theme_switch
        button(
          type: "button", role: "switch", aria_checked: "true",
          aria_label: I18n.t("settings.show.appearance.dark_mode"),
          data: { theme_target: "switch", action: "theme#toggle" },
          class: "relative inline-flex h-7 w-12 shrink-0 items-center rounded-full bg-surface-container-high " \
                 "transition focus:outline-none focus:ring-2 focus:ring-accent-sage/40 aria-checked:bg-accent-sage"
        ) do
          span(
            data: { theme_target: "knob" },
            class: "inline-block h-5 w-5 translate-x-6 rounded-full bg-page transition"
          )
        end
      end

      # --- Move preferences: measurement units (editor-gated segmented toggle) ---
      def preferences_section
        setting_card(I18n.t("settings.show.preferences.title")) do
          setting_row(I18n.t("settings.show.preferences.units")) { unit_toggle }
        end
      end

      def unit_toggle
        if @editable
          div(class: "inline-flex self-start rounded-full border border-card-border bg-card p-1") do
            Move::UNIT_SYSTEMS.each { |system| unit_option(system) }
          end
        else
          resolved_value(I18n.t("settings.show.preferences.#{@move.unit_system}"))
        end
      end

      def unit_option(system)
        label = I18n.t("settings.show.preferences.#{system}")
        if @move.unit_system == system
          span(class: "#{toggle_pill} bg-surface-container-high text-text-warm", aria_current: "true") { label }
        else
          button_to(
            move_settings_unit_system_path(@move), method: :patch,
                                                   params: { move: { unit_system: system } },
                                                   class: "#{toggle_pill} text-on-surface-variant hover:text-text-warm"
          ) { label }
        end
      end

      # --- AI recognition: auto-confirm confidence threshold slider ---
      def recognition_section
        setting_card(I18n.t("settings.show.recognition.title")) do
          div(class: "flex flex-col gap-3") do
            span(class: "text-headline-md text-text-warm") { I18n.t("settings.show.recognition.threshold") }
            @editable ? threshold_slider : resolved_value(format_threshold(@move.auto_confirm_threshold))
            p(class: "text-body-md text-on-surface-variant") do
              I18n.t("settings.show.recognition.threshold_caption")
            end
          end
        end
      end

      def threshold_slider
        form_with(
          url: move_settings_auto_confirm_threshold_path(@move), method: :patch,
          data: { controller: "threshold" }
        ) do
          div(class: "flex items-center gap-4") do
            input(
              type: "range", name: "move[auto_confirm_threshold]", min: "0", max: "1", step: "0.05",
              value: format_threshold(@move.auto_confirm_threshold),
              aria_label: I18n.t("settings.show.recognition.threshold"),
              data: { threshold_target: "input", action: "input->threshold#display change->threshold#submit" },
              class: "h-2 w-full cursor-pointer appearance-none rounded-full bg-surface-container-high " \
                     "accent-accent-sage"
            )
            output(
              data: { threshold_target: "value" },
              class: "w-12 shrink-0 text-right text-headline-md text-accent-sage tabular-nums"
            ) { format_threshold(@move.auto_confirm_threshold) }
          end
          div(class: "mt-2 flex justify-between text-label-caps uppercase text-muted") do
            span { I18n.t("settings.show.recognition.more_handsfree") }
            span { I18n.t("settings.show.recognition.more_review") }
          end
        end
      end

      # --- Assistant & Integrations: MCP tokens (admin-only) ---
      def assistant_section
        render Views::Settings::AssistantPanel.new(
          move: @move, tokens: @tokens, manage_tokens: @manage_tokens, revealed_token: @revealed_token
        )
      end

      # --- Account ---
      def account_section
        sign_out_classes = "rounded-full px-6 py-3 text-body-md font-semibold " \
                           "text-on-surface-variant transition hover:text-error"
        setting_card(I18n.t("settings.show.account.title")) do
          div(class: "flex flex-col gap-3 sm:flex-row") do
            render Components::Ui::Button.new(
              label: I18n.t("settings.show.account.manage"),
              variant: :secondary, href: view_context.account_path
            )
            button_to(
              I18n.t("settings.show.account.sign_out"), view_context.rodauth.logout_path,
              method: :post, class: sign_out_classes
            )
          end
        end
      end

      # --- shared bits ---
      def setting_card(title, &)
        render Components::Ui::Card.new(padding: "p-6") do
          h2(class: "text-headline-md text-text-warm") { title }
          yield
        end
      end

      def setting_row(label, &)
        div(class: "flex items-center justify-between gap-4") do
          span(class: "text-body-lg text-text-warm") { label }
          yield
        end
      end

      def resolved_value(text)
        span(class: "rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") { text }
      end

      def toggle_pill
        "rounded-full px-6 py-2 text-sm font-semibold transition"
      end

      def format_threshold(value)
        # Kernel.format, not the bare format() — Phlex shadows `format`.
        Kernel.format("%.2f", value)
      end

      def time_ago(time)
        "#{view_context.time_ago_in_words(time)} ago"
      end
    end
  end
end
