# frozen_string_literal: true

require "sequel/core"

class RodauthMain < Rodauth::Rails::Auth
  unless BuildTasks.assets_precompile?
    configure do # rubocop:disable Metrics/BlockLength
      # ── Features ──────────────────────────────────────────────
      # Passwordless by design: accounts authenticate with passkeys
      # (WebAuthn), one-time email links, or Google, never a password.
      enable :create_account, :verify_account, :login, :logout,
             :email_auth, :webauthn, :webauthn_login, :webauthn_autofill,
             :omniauth, :remember

      db Sequel.postgres(extensions: :activerecord_connection, keep_reference: false)

      # Schema-qualify every Rodauth table to `public`. Rodauth shares the
      # ActiveRecord connection (sequel-activerecord_connection), whose
      # search_path Apartment switches per tenant. These key tables have no AR
      # model, so Apartment clones them (empty) into each tenant schema;
      # qualifying to public ensures auth always reads the real public rows.
      accounts_table Sequel[:public][:users]
      verify_account_table Sequel[:public][:user_verification_keys]
      email_auth_table Sequel[:public][:user_email_auth_keys]
      webauthn_keys_table Sequel[:public][:user_webauthn_keys]
      webauthn_user_ids_table Sequel[:public][:user_webauthn_user_ids]
      webauthn_keys_account_id_column :user_id

      # ── Remember me (persistent sessions) ─────────────────────
      remember_table Sequel[:public][:user_remember_keys]
      remember_deadline_interval({ days: 30 })
      remember_period({ days: 30 })
      extend_remember_deadline? true
      remember_cookie_options(same_site: :lax)

      # ── OmniAuth (Google social login) ────────────────────────
      # Active only when GOOGLE_CLIENT_ID is configured, so the
      # template runs out of the box without Google credentials.
      omniauth_identities_table Sequel[:public][:user_omniauth_identities]
      omniauth_identities_account_id_column :user_id

      if ENV["GOOGLE_CLIENT_ID"].present?
        omniauth_provider :google_oauth2,
                          ENV["GOOGLE_CLIENT_ID"],
                          ENV.fetch("GOOGLE_CLIENT_SECRET", nil),
                          name: :google,
                          scope: "email,profile"
      end

      # Self-service signup is open, so let Google create accounts too.
      omniauth_create_account? true
      omniauth_verify_account? true

      omniauth_identity_insert_hash do
        super().merge(id: SecureRandom.uuid)
      end

      rails_controller { RodauthController }
      title_instance_variable :@page_title

      account_status_column :status
      login_param "email"
      login_label "Email"
      login_confirm_param "email-confirm"

      # Friendlier copy for the multi-phase (email-first) login flow.
      need_password_notice_flash "Email recognized. Choose how to sign in."
      email_auth_email_sent_notice_flash "A sign-in link has been sent to your email. Check your inbox."
      email_auth_email_sent_redirect { login_path }

      create_account_set_password? false
      verify_account_set_password? false
      require_login_confirmation? false
      require_password_confirmation? false
      require_bcrypt? false

      auth_class_eval do
        # No second factor is wired up; keeps the :webauthn feature from
        # treating passkeys as a 2FA step.
        def two_factor_authentication_setup?
          false
        end

        def get_password_hash
          nil
        end

        # Name a newly registered passkey: prefer the name the user typed,
        # else resolve it from the authenticator's AAGUID, else guess from
        # the User-Agent. See app/misc/webauthn/*.
        def webauthn_key_insert_hash(webauthn_credential)
          super.merge(name: resolve_passkey_name(webauthn_credential))
        end

        def resolve_passkey_name(webauthn_credential)
          submitted = param_or_nil("passkey_name").to_s.strip
          return submitted[0, 80] if submitted.present?

          aaguid = extract_aaguid(webauthn_credential)
          Webauthn::AaguidLookup.lookup(aaguid) ||
            Webauthn::NameSuggester.from_user_agent(request.user_agent)
        end

        def extract_aaguid(webauthn_credential)
          webauthn_credential
            .response
            .authenticator_data
            .attested_credential_data
            &.aaguid
        rescue StandardError
          nil
        end

        def before_create_account
          super
          account[:id] ||= SecureRandom.uuid
          timestamp = Time.current
          account[:created_at] ||= timestamp
          account[:updated_at] ||= timestamp
        end

        # Verify accounts without forcing a password step (we are
        # passwordless), then auto-login and respond.
        def verify_account_view
          return super if verify_account_set_password? || !account

          transaction do
            before_verify_account
            verify_account
            clear_tokens(:verify_account)
            after_verify_account
          end

          autologin_session("verify_account") if verify_account_autologin?
          remove_session_value(verify_account_session_key)
          verify_account_response
        end
      end

      email_from do
        ENV.fetch("RODAUTH_FROM", ENV.fetch("NOTIF_MAIL_FROM", "no-reply@example.com"))
      end

      create_verify_account_email do
        RodauthMailer.verify_account(self.class.configuration_name, account_id, verify_account_key_value)
      end

      create_email_auth_email do
        RodauthMailer.email_auth(self.class.configuration_name, account_id, email_auth_key_value)
      end

      send_email do |email|
        db.after_commit { email.deliver_later }
      end

      webauthn_origin { ENV.fetch("WEBAUTHN_ORIGIN", base_url) }
      webauthn_rp_id do
        ENV.fetch("WEBAUTHN_RP_ID", webauthn_origin.sub(%r{\Ahttps?://}, "").sub(/:\d+\z/, ""))
      end
      webauthn_rp_name { ENV.fetch("WEBAUTHN_RP_NAME", Rails.application.config.x.brand_name) }
      webauthn_user_verification "preferred"

      # ── OmniAuth hooks ────────────────────────────────────────
      omniauth_login_failure_redirect { login_path }

      after_login do
        remember_login

        # Backfill the user's name from the Google profile on first login.
        next unless authenticated_by&.include?("omniauth")
        next if omniauth_name.blank?

        user = ::User.find_by(id: account_id)
        user&.update!(name: omniauth_name) if user&.name.blank?
      end

      logout_redirect "/"
      verify_account_redirect { login_redirect }
    end
  end
end
