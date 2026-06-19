# frozen_string_literal: true

module Views
  module Rodauth
    class WebauthnRemove < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ContentTag
      include Phlex::Rails::Helpers::LinkTo

      # Tailwind must see these literals to compile them — the passkey-list
      # controller adds the same tokens to localStorage-matched rows at runtime.
      HIGHLIGHT_CLASSES = "ring-2 ring-[var(--ha-primary)]"

      def view_template
        div(
          class: "space-y-8",
          data: { controller: "passkey-list", passkey_list_account_value: account_id }
        ) do
          render_hero
          render Components::RodauthFlash.new
          # Hide "Add another" when this device already has a passkey (the one it
          # signed in with / just added). When unknown (email-link session) the
          # card renders and the controller hides it if this browser created one.
          render_add_another_card unless current_device_id
          render_remove_form
        end
      end

      private

      def account_id
        view_context.rodauth.account_id
      end

      # The credential this session authenticated with (or just registered);
      # nil on an email-link session. Marks "the current device's passkey".
      def current_device_id
        return @current_device_id if defined?(@current_device_id)

        @current_device_id = view_context.rodauth.authenticated_webauthn_id
      end

      def render_hero
        div(class: "ha-card p-8") do
          p(class: "ha-overline") { plain "Security" }
          h1(class: "mt-2 text-3xl font-semibold tracking-tight sm:text-4xl") do
            plain "Manage passkeys"
          end
          p(class: "mt-3 text-sm text-[var(--ha-muted)]") do
            plain "Remove a passkey that you no longer use."
          end
        end
      end

      def render_add_another_card
        div(class: "ha-card p-6", data: { passkey_list_target: "addCard" }) do
          h2(class: "text-lg font-semibold") { plain "Add another passkey" }
          p(class: "mt-2 text-sm text-[var(--ha-muted)]") do
            plain "Register another device for faster, safer sign-ins."
          end
          div(class: "mt-4") do
            link_to(
              "Add passkey",
              view_context.rodauth.webauthn_setup_path,
              class: "ha-button ha-button-primary"
            )
          end
        end
      end

      def render_remove_form
        div(class: "ha-card p-6 space-y-6") do
          form_with(
            url: view_context.rodauth.webauthn_remove_path,
            method: :post,
            id: "webauthn-remove-form",
            data: { turbo: false },
            class: "space-y-6"
          ) do |form|
            raw safe(view_context.rodauth.webauthn_remove_additional_form_tags.to_s)

            div(class: "flex flex-col gap-3") do
              # Pre-select the first key so a submit always carries a valid
              # webauthn_remove value (Rodauth rejects an empty selection with
              # "must select a valid webauthn authenticator to remove").
              passkey_rows.each_with_index do |row, i|
                render_passkey_row(form, row, checked: i.zero?,
                                              current: row[:id] == current_device_id)
              end
            end

            render_remove_error

            form.submit(
              view_context.rodauth.webauthn_remove_button,
              class: "ha-button ha-button-danger w-full"
            )
          end
        end
      end

      def render_passkey_row(form, row, checked: false, current: false)
        label(
          for: "webauthn-remove-#{row[:id]}",
          data: { passkey_list_target: "row", webauthn_id: row[:id] },
          class: [
            "flex cursor-pointer items-center gap-3 rounded-xl border " \
            "border-[var(--ha-border)] bg-[var(--ha-surface-muted)] px-3 py-2 " \
            "text-sm text-[var(--ha-text)]",
            (current ? HIGHLIGHT_CLASSES : "")
          ].join(" ").strip
        ) do
          form.radio_button(
            view_context.rodauth.webauthn_remove_param,
            row[:id],
            id: "webauthn-remove-#{row[:id]}",
            checked: checked,
            class: "h-4 w-4",
            aria: radio_aria_attrs
          )
          div(class: "flex min-w-0 flex-1 flex-col") do
            div(class: "flex items-center gap-2") do
              span(class: "truncate font-medium") { plain row[:name] }
              render_this_device_badge(hidden: !current)
            end
            span(class: "text-xs text-[var(--ha-muted)]") do
              plain "Last used: #{row[:last_use]}"
            end
          end
        end
      end

      # Always in the DOM (hidden by default); revealed server-side for the
      # signed-in-with credential, and by the passkey-list controller for rows
      # this browser registered (localStorage).
      def render_this_device_badge(hidden:)
        span(
          data: { passkey_list_target: "badge" },
          class: [
            "inline-flex shrink-0 items-center rounded-full px-2 py-0.5 " \
            "text-[10px] font-bold uppercase tracking-wide " \
            "bg-[var(--ha-primary-container)]/30 text-[var(--ha-primary)]",
            (hidden ? "hidden" : "")
          ].join(" ").strip
        ) { plain "This device" }
      end

      def render_remove_error
        return unless remove_error

        span(
          class: "block text-xs text-red-500",
          id: "webauthn_remove_error_message"
        ) { remove_error }
      end

      def radio_aria_attrs
        return {} unless remove_error

        { invalid: true, describedby: "webauthn_remove_error_message" }
      end

      def remove_error
        return @remove_error if defined?(@remove_error)

        @remove_error = view_context.rodauth.field_error(
          view_context.rodauth.webauthn_remove_param
        )
      end

      def passkey_rows
        rodauth = view_context.rodauth
        fmt = rodauth.strftime_format
        # Schema-qualify to public: this row has no AR model, so on an org
        # subdomain Apartment's search_path points at the (empty) tenant-cloned
        # copy. Without `public.` the list renders zero keys and removal always
        # fails. Mirrors the rodauth_main webauthn_keys_table qualification.
        sql = ActiveRecord::Base.sanitize_sql_array(
          [
            "SELECT webauthn_id, last_use, name FROM public.user_webauthn_keys " \
            "WHERE user_id = ? ORDER BY last_use DESC",
            rodauth.account_id
          ]
        )
        rows = ActiveRecord::Base.connection.exec_query(sql, "Passkeys")
        rows.map do |row|
          last_use = row["last_use"]
          parsed = last_use.is_a?(Time) ? last_use : Time.zone.parse(last_use.to_s)
          { id: row["webauthn_id"],
            name: row["name"].presence || "Passkey",
            last_use: parsed ? parsed.strftime(fmt) : "Never" }
        end
      end
    end
  end
end
