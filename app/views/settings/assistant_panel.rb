# frozen_string_literal: true

module Views
  module Settings
    # F3 — Assistant & Integrations panel (a section of the Settings screen).
    # Admin-only: a create-token form, the one-time raw-token reveal, and the
    # active-token list with per-token metadata and a revoke action. Non-admins
    # see only an explanatory note. Extracted from Settings::Show so each class
    # stays focused (and under the length limit).
    class AssistantPanel < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      #: (move: untyped, tokens: untyped, manage_tokens: untyped, ?can_create: untyped, ?revealed_token: untyped) -> void
      def initialize(move:, tokens:, manage_tokens:, can_create: true, revealed_token: nil)
        @move = move
        @tokens = tokens
        @manage_tokens = manage_tokens
        @can_create = can_create
        @revealed_token = revealed_token
      end

      #: () -> void
      def view_template
        section(id: "assistant", aria_label: I18n.t("integration_tokens.panel.title")) do
          render Components::Ui::Card.new(padding: "p-6") do
            div(class: "flex flex-col gap-2") do
              h2(class: "text-headline-md text-text-warm") { I18n.t("integration_tokens.panel.title") }
              p(class: "text-body-md text-on-surface-variant") { I18n.t("integration_tokens.panel.subtitle") }
            end
            if @manage_tokens
              revealed_token_block if @revealed_token
              create_token_form if @can_create
              token_list
            else
              p(class: "text-body-md text-muted") { I18n.t("integration_tokens.panel.admin_only") }
            end
          end
        end
      end

      private

      #: () -> untyped
      def create_token_form
        # turbo: false — create renders the settings page inline (200) to reveal
        # the raw token once. Turbo Drive ignores a non-redirect 200 on form
        # submit, so the reveal would never show; a full navigation renders it.
        form_with(url: move_integration_tokens_path(@move), method: :post, data: { turbo: false }) do
          div(class: "flex flex-col gap-4 sm:flex-row sm:items-end") do
            div(class: "flex-1") do
              render Components::Ui::Field.new(
                name: "integration_token[name]",
                label: I18n.t("integration_tokens.panel.name_label"),
                placeholder: I18n.t("integration_tokens.panel.name_placeholder"),
                required: true
              )
            end
            render Components::Ui::Button.new(
              label: I18n.t("integration_tokens.panel.submit"),
              icon: Components::Icons::Plus, type: "submit"
            )
          end
        end
      end

      # The one-and-only display of the raw token, with a copy button.

      #: () -> untyped
      def revealed_token_block
        div(
          class: "flex flex-col gap-3 rounded-card border border-accent-sage/40 bg-surface-container-high p-4",
          data: { controller: "clipboard" }
        ) do
          div(class: "flex flex-col gap-1") do
            span(class: "text-headline-md text-text-warm") { I18n.t("integration_tokens.reveal.title") }
            span(class: "text-body-md text-on-surface-variant") { I18n.t("integration_tokens.reveal.body") }
          end
          div(class: "flex items-center gap-3") do
            code(
              data: { clipboard_target: "source" },
              class: "flex-1 overflow-x-auto rounded-card bg-page px-4 py-3 font-mono text-body-md text-accent-sage"
            ) { @revealed_token }
            render Components::Ui::Button.new(
              label: I18n.t("integration_tokens.reveal.copy"), variant: :secondary,
              data: { action: "clipboard#copy" }
            )
          end
        end
      end

      #: () -> untyped
      def token_list
        active = @tokens.reject(&:revoked?)
        if active.empty?
          p(class: "text-body-md text-muted") { I18n.t("integration_tokens.panel.empty") }
        else
          div(class: "flex flex-col gap-3") { active.each { |token| token_row(token) } }
        end
      end

      #: (untyped token) -> untyped
      def token_row(token)
        article(
          class: "flex items-center justify-between gap-4 rounded-card border border-card-border bg-card p-4"
        ) do
          div(class: "flex min-w-0 flex-col gap-1") do
            span(class: "truncate text-headline-md text-text-warm") { token.name }
            span(class: "text-body-md text-on-surface-variant") { token_meta(token) }
          end
          revoke_button(token)
        end
      end

      #: (untyped token) -> untyped
      def revoke_button(token)
        confirm = I18n.t("integration_tokens.token.revoke_confirm", name: token.name)
        classes = "rounded-full px-4 py-2 text-body-md font-semibold text-on-surface-variant " \
                  "transition hover:bg-error/10 hover:text-error"
        button_to(
          move_integration_token_path(@move, token), method: :delete,
                                                     form: { data: { turbo_confirm: confirm } }, class: classes
        ) { I18n.t("integration_tokens.token.revoke") }
      end

      #: (untyped token) -> String
      def token_meta(token)
        creator = token.created_by&.name.presence || token.created_by&.email.to_s.split("@").first
        used = if token.last_used_at
                 I18n.t("integration_tokens.token.last_used", time: time_ago(token.last_used_at))
               else
                 I18n.t("integration_tokens.token.never_used")
               end
        "#{I18n.t("integration_tokens.token.created_by", name: creator)} · #{used}"
      end

      #: (untyped time) -> String
      def time_ago(time)
        "#{view_context.time_ago_in_words(time)} ago"
      end
    end
  end
end
